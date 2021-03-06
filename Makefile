OCAMLC=ocamlfind ocamlc
CHECKER=ocsigen-i18n-checker
REWRITER=ocsigen-i18n-rewriter
GENERATOR=ocsigen-i18n-generator

PROGS=${GENERATOR} ${REWRITER} ${CHECKER}

build: ${PROGS}

${GENERATOR}: i18n_generate.mll
	ocamllex i18n_generate.mll
	${OCAMLC} -package str -linkpkg -o $@ i18n_generate.ml

$(CHECKER): i18n_ppx_common.ml i18n_ppx_checker.ml
	${OCAMLC} -package str -package compiler-libs.common -linkpkg -o $@ $^

${REWRITER}: i18n_ppx_common.ml i18n_ppx_rewriter.ml
	${OCAMLC} -package str -package compiler-libs.common -linkpkg -o $@ $^

clean:
	-rm -f *.cmi *.cmo *~ *#
	-rm -f i18n_generate.ml
	-rm -f ${GENERATOR} ${REWRITER} ${CHECKER}

install: ${PROGS}
ifndef bindir
	${error bindir is not set}
else
	cp ${PROGS} ${bindir}
endif
