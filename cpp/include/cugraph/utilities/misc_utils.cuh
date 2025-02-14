/*
 * Copyright (c) 2021-2024, NVIDIA CORPORATION.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
#pragma once

#include <raft/core/device_span.hpp>
#include <raft/core/handle.hpp>
#include <raft/util/cudart_utils.hpp>

#include <rmm/device_uvector.hpp>

#include <cuda/atomic>
#include <cuda/functional>
#include <thrust/binary_search.h>
#include <thrust/gather.h>
#include <thrust/iterator/counting_iterator.h>
#include <thrust/iterator/transform_iterator.h>
#include <thrust/optional.h>

#include <optional>
#include <tuple>
#include <vector>

namespace cugraph {

namespace detail {

template <typename vertex_t, typename edge_t>
std::tuple<std::vector<vertex_t>, std::vector<edge_t>> compute_offset_aligned_edge_chunks(
  raft::handle_t const& handle,
  edge_t const* offsets,
  vertex_t num_vertices,
  edge_t num_edges,
  size_t approx_edge_chunk_size)
{
  auto search_offset_first = thrust::make_transform_iterator(
    thrust::make_counting_iterator(size_t{1}),
    cuda::proclaim_return_type<size_t>(
      [approx_edge_chunk_size] __device__(auto i) { return i * approx_edge_chunk_size; }));
  auto num_chunks = (num_edges + approx_edge_chunk_size - 1) / approx_edge_chunk_size;

  if (num_chunks > 1) {
    rmm::device_uvector<vertex_t> d_vertex_offsets(num_chunks - 1, handle.get_stream());
    thrust::lower_bound(handle.get_thrust_policy(),
                        offsets,
                        offsets + num_vertices + 1,
                        search_offset_first,
                        search_offset_first + d_vertex_offsets.size(),
                        d_vertex_offsets.begin());
    rmm::device_uvector<edge_t> d_edge_offsets(d_vertex_offsets.size(), handle.get_stream());
    thrust::gather(handle.get_thrust_policy(),
                   d_vertex_offsets.begin(),
                   d_vertex_offsets.end(),
                   offsets,
                   d_edge_offsets.begin());
    std::vector<edge_t> h_edge_offsets(num_chunks + 1, edge_t{0});
    h_edge_offsets.back() = num_edges;
    raft::update_host(
      h_edge_offsets.data() + 1, d_edge_offsets.data(), d_edge_offsets.size(), handle.get_stream());
    std::vector<vertex_t> h_vertex_offsets(num_chunks + 1, vertex_t{0});
    h_vertex_offsets.back() = num_vertices;
    raft::update_host(h_vertex_offsets.data() + 1,
                      d_vertex_offsets.data(),
                      d_vertex_offsets.size(),
                      handle.get_stream());

    handle.sync_stream();

    return std::make_tuple(h_vertex_offsets, h_edge_offsets);
  } else {
    return std::make_tuple(std::vector<vertex_t>{{0, num_vertices}},
                           std::vector<edge_t>{{0, num_edges}});
  }
}

template <typename T>
thrust::optional<T> to_thrust_optional(std::optional<T> val)
{
  thrust::optional<T> ret{thrust::nullopt};
  if (val) { ret = *val; }
  return ret;
}

template <typename idx_t, typename offset_t>
rmm::device_uvector<idx_t> expand_sparse_offsets(raft::device_span<offset_t const> offsets,
                                                 idx_t base_idx,
                                                 rmm::cuda_stream_view stream_view)
{
  assert(offsets.size() > 0);

  offset_t num_entries{0};
  raft::update_host(&num_entries, offsets.data() + offsets.size() - 1, 1, stream_view);

  rmm::device_uvector<idx_t> results(num_entries, stream_view);

  if (num_entries > 0) {
    thrust::fill(rmm::exec_policy(stream_view), results.begin(), results.end(), idx_t{0});

    if (base_idx != idx_t{0}) { raft::update_device(results.data(), &base_idx, 1, stream_view); }

    thrust::for_each(
      rmm::exec_policy(stream_view),
      offsets.begin() + 1,
      offsets.end(),
      [results =
         raft::device_span<idx_t>(results.data(), results.size())] __device__(offset_t offset) {
        if (offset < static_cast<offset_t>(results.size())) {
          cuda::atomic_ref<idx_t, cuda::thread_scope_device> atomic_counter(results[offset]);
          atomic_counter.fetch_add(idx_t{1}, cuda::std::memory_order_relaxed);
        }
      });
    thrust::inclusive_scan(
      rmm::exec_policy(stream_view), results.begin(), results.end(), results.begin());
  }

  return results;
}

}  // namespace detail

}  // namespace cugraph
