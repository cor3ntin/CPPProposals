OUT=$(realpath .)/generated
SRC=$(realpath .)/src
SRCS=$(wildcard $(SRC)/*.tex)
OUTS=$(patsubst $(SRC)/%.tex,$(OUT)/%.pdf,$(SRCS))
OUTS:=$(subst .tex,.pdf,$(OUTS))
OUTS_HTML=$(patsubst $(SRC)/%.tex,$(OUT)/%.html,$(SRCS))
OUTS_HTML:=$(subst .tex,.html,$(OUTS_HTML))

export TEXINPUTS = $(SRC):$(SRC)/../emojis

all: pdfs

pdfs: mkoutput $(OUTS) $(OUTS_HTML)
	cd $(OUT) && rm *.log *.aux *.xtr 2>/dev/null; true

mkoutput:
	mkdir -p $(OUT)

$(OUT)/%.pdf: $(SRC)/%.tex
	cd $(OUT) && lualatex -shell-escape --interaction=batchmode $<

$(OUT)/%.html: $(SRC)/%.tex
	cd $(OUT) && htlatex $< "html,fn-in" && bibtex  $< && htlatex $< "html,fn-in" && htlatex $< "html,fn-in"

bib:
	wget https://wg21.link/index.bib -O $(SRC)/wg21.bib

clean:
	rm -r $(OUT)