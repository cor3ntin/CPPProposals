# Builds the Markdown papers in this directory with the MPark/WG21 framework
# (https://github.com/mpark/wg21), alongside the LaTeX papers built by the
# top-level Makefile.
#
#   make                          # every paper, HTML
#   make html | pdf | latex       # every paper, in one format
#   make P3606R1                  # one paper by document number, HTML
#   make P3606R1.pdf              # ... in another format (pdf needs LaTeX)
#   make overload_resolution.html # or by file name
#   make papers                   # list the document number of each paper
#   make clean
#
# The framework is not vendored here; clone it separately and point WG21_DIR at
# it if it does not live in ~/wg21:
#
#   git clone https://github.com/mpark/wg21.git ~/wg21
#
# It downloads its own pinned Pandoc and Python virtualenv into wg21/deps on
# first use, so the system Pandoc version does not matter.

WG21_DIR ?= $(HOME)/wg21

ifeq ($(wildcard $(WG21_DIR)/flat.mk),)
$(error MPark/WG21 not found in $(WG21_DIR). Clone https://github.com/mpark/wg21 \
or set WG21_DIR to an existing checkout)
endif

OUTDIR := ../generated

include $(WG21_DIR)/flat.mk

# flat.mk derives every target from the source file name. Papers are named after
# their subject rather than their number, so also expose each one under the
# document number in its YAML front matter.
docnum = $(shell sed -n 's/^document:[[:space:]]*"\{0,1\}\([A-Za-z0-9]\{1,\}\).*/\1/p' $(1) | head -1)

# $(1) is the source file, $(2) its document number.
define paper_alias
ifneq ($(2),)
.PHONY: $(2) $(2).html $(2).pdf $(2).latex
$(2): $(2).html
$(2).html: $(basename $(1)).html
$(2).pdf: $(basename $(1)).pdf
$(2).latex: $(basename $(1)).latex
endif
endef

$(foreach s,$(src),$(eval $(call paper_alias,$(s),$(call docnum,$(s)))))

.PHONY: papers
papers:
	@$(foreach s,$(src),printf '%-12s %s\n' '$(call docnum,$(s))' '$(s)';)
