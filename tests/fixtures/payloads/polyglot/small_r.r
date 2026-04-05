#' Build and check a package
#'
#' @description
#' `check()` automatically builds and checks a source package, using all known
#' best practices. `check_built()` checks an already-built package.
#'
#' Passing `R CMD check` is essential if you want to submit your package to
#' CRAN: you must not have any ERRORs or WARNINGs, and you want to ensure that
#' there are as few NOTEs as possible.  If you are not submitting to CRAN, at
#' least ensure that there are no ERRORs or WARNINGs: these typically represent
#' serious problems.
#'
#' `check()` automatically builds a package before calling `check_built()`, as
#' this is the recommended way to check packages.  Note that this process runs
#' in an independent R session, so nothing in your current workspace will affect
#' the process. Under-the-hood, `check()` and `check_built()` rely on
#' [pkgbuild::build()] and [rcmdcheck::rcmdcheck()].
#'
#' @section Environment variables:
#'
#' Devtools does its best to set up an environment that combin
