# Minimal makefile for Sphinx documentation
#

# You can set these variables from the command line.
SPHINXOPTS    = "-v"
SPHINXBUILD   = sphinx-build
SPHINXPROJ    = cugraph
SOURCEDIR     = source
BUILDDIR      = build
IMGDIR        = images

gen_doc_dirs  = build source/api_docs/api
# Put it first so that "make" without argument is like "make help".
help:
	@$(SPHINXBUILD) -M help "$(SOURCEDIR)" "$(BUILDDIR)" $(SPHINXOPTS) $(O)

.PHONY: help Makefile clean

# clean to remove all the generated documentation files in build and source
clean:
	rm -rf $(gen_doc_dirs)

# Catch-all target: route all unknown targets to Sphinx using the new
# "make mode" option.  $(O) is meant as a shortcut for $(SPHINXOPTS).
%: Makefile
	@$(SPHINXBUILD) -M $@ "$(SOURCEDIR)" "$(BUILDDIR)" $(SPHINXOPTS) $(O)