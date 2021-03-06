#' Launch test event recorder for a Shiny app
#'
#' @param app A \code{\link{ShinyDriver}} object, or path to a Shiny
#'   application.
#' @param save_dir A directory to save stuff.
#' @param load_mode A boolean that determines whether or not the resulting test
#'   script should be appropriate for load testing.
#' @param seed A random seed to set before running the app. This seed will also
#'   be used in the test script.
#' @param loadTimeout Maximum time to wait for the Shiny application to load, in
#'   milliseconds. If a value is provided, it will be saved in the test script.
#' @param shinyOptions A list of options to pass to \code{runApp()}. If a value
#'   is provided, it will be saved in the test script.
#' @export
recordTest <- function(app = ".", save_dir = NULL, load_mode = FALSE, seed = NULL,
  loadTimeout = 10000, shinyOptions = list()) {

  # Get the URL for the app. Depending on what type of object `app` is, it may
  # require starting an app.
  if (inherits(app, "ShinyDriver")) {
    url <- app$getUrl()
  } else if (is.character(app)) {
    if (grepl("^http(s?)://", app)) {
      stop("Recording tests for remote apps is not yet supported.")
    } else {
      app <- app_path(app)

      if (is_rmd(app)) {
        # If it's an Rmd file, make sure there aren't multiple Rmds in that
        # directory.
        if (length(dir(dirname(app), pattern = "\\.Rmd$", ignore.case = TRUE)) > 1) {
          stop("For testing, only one .Rmd file is allowed per directory.")
        }

        # Rmds need a random seed. Automatically create one if needed.
        if (is.null(seed)) {
          seed <- floor(stats::runif(1, min = 0, max = 1e5))
        }
      }

      # It's a path to an app; start the app
      app <- ShinyDriver$new(app, seed = seed, loadTimeout = loadTimeout, shinyOptions = shinyOptions)
      on.exit({
        rm(app)
        gc()
      })
      url <- app$getUrl()
    }
  } else if (inherits(app, "shiny.appobj")) {
    stop("Recording tests for shiny.appobj objects is not supported.")
  } else {
    stop("Unknown object type to record tests for.")
  }

  # Create directory if needed
  if (is.null(save_dir)) {
    save_dir <- file.path(app$getAppDir(), "tests")
    if (!dir_exists(save_dir)) {
      dir.create(save_dir)
    }
    save_dir <- normalizePath(save_dir)
  }

  # Use options to pass value to recorder app
  withr::with_options(
    list(
      shinytest.recorder.url  = url,
      shinytest.app.dir       = app$getAppDir(),
      shinytest.app.filename  = app$getAppFilename(),
      shinytest.load.mode     = load_mode,
      shinytest.load.timeout  = if (!missing(loadTimeout)) loadTimeout,
      shinytest.seed          = seed,
      shinytest.shiny.options = shinyOptions
    ),
    res <- shiny::runApp(system.file("recorder", package = "shinytest"))
  )

  if (is.null(res$appDir)) {
    # Quit without saving

  } else if (isTRUE(res$run)) {

    # Before running the test, sometimes we need to make sure the previous run
    # of the app is shut down. For example, if a port is specified in
    # shinyOptions, it needs to be freed up before starting the app again.
    gc()

    # Run the test script
    testApp(rel_path(res$appDir), res$file)

  } else {
    if (length(res$dont_run_reasons) > 0) {
      message(
        "Not running test script because:\n  ",
        paste(res$dont_run_reasons, collapse = "\n  "), "\n"
      )
    }

    message(sprintf(
      'After making changes to the test script, run it with:\n  testApp("%s", "%s")',
      rel_path(res$appDir), res$file
    ))
  }

  invisible(res$file)
}


# Evaluates an expression (like `runApp()`) with the shiny.http.response.filter
# option set to a function which rewrites the <head> to include recorder.js.
with_shinyrecorder <- function(expr) {
  shiny::addResourcePath(
    "shinytest",
    system.file("js", package = "shinytest")
  )

  filter <- function(request, response) {
    if (response$status < 200 || response$status > 300) return(response)

    # Don't break responses that use httpuv's file-based bodies.
    if ('file' %in% names(response$content))
      return(response)

    if (!grepl("^text/html\\b", response$content_type, perl=T))
      return(response)

    # HTML files served from static handler are raw. Convert to char so we
    # can inject our head content.
    if (is.raw(response$content))
      response$content <- rawToChar(response$content)

    # Modify the <head> to load shinytest.js
    response$content <- sub(
      "</head>",
      "<script src=\"shared/jqueryui/jquery-ui.min.js\"></script>
      <script src=\"shinytest/recorder.js\"></script>\n</head>",
      response$content,
      ignore.case = TRUE
    )

    return(response)
  }

  if (!is.null(getOption("shiny.http.response.filter"))) {
    # If there's an existing filter, create a wrapper function that first runs
    # the old filter and then the new one on the request.
    old_filter <- getOption("shiny.http.response.filter")

    wrapper_filter <- function(request, response) {
      filter(old_filter(request, response))
    }

    withr::with_options(
      list(shiny.http.response.filter = wrapper_filter, shiny.testmode = TRUE),
      expr
    )

  } else {
    withr::with_options(
      list(shiny.http.response.filter = filter, shiny.testmode = TRUE),
      expr
    )
  }
}