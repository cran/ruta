#' Create an autoencoder learner
#'
#' Internal function to create autoencoder objects. Instead, consider using
#' `\link{autoencoder}`.
#' @param network Layer construct of class `"ruta_network"` or coercible
#' @param loss A `"ruta_loss"` object or a character string specifying a loss function
#' @param extra_class Vector of classes in case this autoencoder needs to support custom
#'   methods (for `to_keras`, `train`, `generate` or others)
#' @return A construct of class `"ruta_autoencoder"`
#' @export
new_autoencoder <- function(network, loss, extra_class = NULL) {
  structure(
    list(
      network = as_network(network),
      loss = as_loss(loss)
    ),
    class = c(extra_class, ruta_autoencoder, ruta_learner)
  )
}

#' Create an autoencoder learner
#'
#' Represents a generic autoencoder network.
#' @param network Layer construct of class `"ruta_network"` or coercible
#' @param loss A `"ruta_loss"` object or a character string specifying a loss function
#' @return A construct of class `"ruta_autoencoder"`
#' @seealso \code{\link{train.ruta_autoencoder}}
#'
#' @references
#' - [A practical tutorial on autoencoders for nonlinear feature fusion](https://arxiv.org/abs/1801.01586)
#'
#' @family autoencoder variants
#' @examples
#'
#' # Basic autoencoder with a network of [input]-256-36-256-[input] and
#' # no nonlinearities
#' autoencoder(c(256, 36), loss = "binary_crossentropy")
#'
#' # Customizing the activation functions in the same network
#' network <-
#'   input() +
#'   dense(256, "relu") +
#'   dense(36, "tanh") +
#'   dense(256, "relu") +
#'   output("sigmoid")
#'
#' learner <- autoencoder(
#'   network,
#'   loss = "binary_crossentropy"
#' )
#'
#' @export
autoencoder <- function(network, loss = "mean_squared_error") {
  new_autoencoder(network, loss)
}

#' Inspect Ruta objects
#'
#' @param x An object
#' @param ... Unused
#' @return Invisibly returns the same object passed as parameter
#' @examples
#' print(autoencoder(c(256, 10), loss = correntropy()))
#' @rdname print-methods
#' @export
print.ruta_autoencoder <- function(x, ...) {
  cat("Autoencoder learner\n")
  type <- NULL

  if (is_sparse(x)) type <- c(type, "sparse")
  if (is_contractive(x)) type <- c(type, "contractive")
  if (is_robust(x)) type <- c(type, "robust")
  if (is_denoising(x)) type <- c(type, "denoising")
  if (is_variational(x)) type <- c(type, "variational")
  type <- if (is.null(type)) "basic" else paste0(type, collapse = ", ")

  print_line()
  cat("Type:", type, "\n\n")
  print(x$network)
  cat("\n")
  print(x$loss)
  print_line()

  invisible(x)
}

#' Detect trained models
#'
#' Inspects a learner and figures out whether it has been trained
#'
#' @param learner Learner object
#' @return A boolean
#' @seealso `\link{train}`
#' @export
is_trained <- function(learner) {
  !is.null(learner$models)
}

#' Extract Keras models from an autoencoder wrapper
#'
#' @param x Object of class \code{"ruta_autoencoder"}. Needs to have a member
#'   `input_shape` indicating the number of attributes of the input data
#' @param encoder_end Name of the Keras layer where the encoder ends
#' @param decoder_start Name of the Keras layer where the decoder starts
#' @param weights_file The name of a hdf5 weights file in order to load from a trained model
#' @param ... Unused
#' @return A list with several Keras models:
#' - `autoencoder`: model from the input layer to the output layer
#' - `encoder`: model from the input layer to the encoding layer
#' - `decoder`: model from the encoding layer to the output layer
#' @importFrom purrr detect_index
#' @seealso `\link{autoencoder}`
#' @export
to_keras.ruta_autoencoder <- function(x, encoder_end = "encoding", decoder_start = "encoding", weights_file = NULL, ...) {
  # end-to-end autoencoder
  model <- to_keras(x$network, x$input_shape)

  # load HDF5 weights if required
  if (!is.null(weights_file)) {
    message("Loading weights from ", weights_file)
    keras::load_model_weights_hdf5(model, weights_file)
  }

  # encoder, from inputs to latent space
  encoding_layer <- keras::get_layer(model, encoder_end)
  encoder <- keras::keras_model(model$input, encoding_layer$output)

  # decoder, from latent space to reconstructed inputs
  encoding_dim <- keras::get_layer(model, decoder_start)$output_shape[-1]
  decoder_input <- keras::layer_input(shape = encoding_dim)

  # re-build the decoder taking layers from the model
  start <- detect_index(model$layers, ~ .$name == decoder_start)
  end <- length(model$layers) - 1

  decoder_stack <- decoder_input
  for (lay_i in start:end) {
    # one-based index
    decoder_stack <- keras::get_layer(model, index = lay_i + 1)(decoder_stack)
  }

  decoder <- keras::keras_model(decoder_input, decoder_stack)

  list(
    autoencoder = model,
    encoder = encoder,
    decoder = decoder
  )
}

#' Configure a learner object with the associated Keras objects
#'
#' This function builds all the necessary Keras objects in order
#' to manipulate internals of the models or train them. Users won't generally
#' need to call this function, since \code{train} will do so automatically.
#' @param learner A \code{"ruta_autoencoder"} object
#' @param input_shape An integer describing the number of variables in the input data
#' @return Same learner passed as parameter, with new members \code{input_shape},
#'  \code{models} and \code{keras_loss}
#' @importFrom tensorflow tf
#' @export
configure <- function(learner, input_shape) {
  tensorflow::tf$compat$v1$disable_eager_execution()
  if (is.null(learner$input_shape) || learner$input_shape != input_shape) {
    learner$input_shape <- input_shape
    learner$models <- NULL
    learner$keras_loss <- NULL
  }
  if (is.null(learner$models))
    learner$models <- to_keras(learner)
  if (is.null(learner$keras_loss))
    learner$keras_loss <- to_keras(learner$loss, learner)

  invisible(learner)
}


#' Train a learner object with data
#'
#' This function compiles the neural network described by the learner object
#' and trains it with the input data.
#' @param learner A \code{"ruta_autoencoder"} object
#' @param data Training data: columns are attributes and rows are instances
#' @param validation_data Additional numeric data matrix which will not be used
#'   for training but the loss measure and any metrics will be computed against it
#' @param metrics Optional list of metrics which will evaluate the model but
#'   won't be optimized. See `keras::\link[keras]{compile}`
#' @param epochs The number of times data will pass through the network
#' @param optimizer The optimizer to be used in order to train the model, can
#'   be any optimizer object defined by Keras (e.g. `keras::optimizer_adam()`)
#' @param ... Additional parameters for `keras::\link[keras]{fit}`. Some useful parameters:
#'   - `batch_size` The number of examples to be grouped for each gradient update.
#'     Use a smaller batch size for more frequent weight updates or a larger one for
#'     faster optimization.
#'   - `shuffle` Whether to shuffle the training data before each epoch, defaults to `TRUE`
#' @return Same autoencoder passed as parameter, with trained internal models
#' @examples
#' # Minimal example ================================================
#' \donttest{
#' if (interactive() && keras::is_keras_available())
#'   iris_model <- train(autoencoder(2), as.matrix(iris[, 1:4]))
#' }
#'
#' # Simple example with MNIST ======================================
#' \donttest{
#' library(keras)
#' if (interactive() && keras::is_keras_available()) {
#'   # Load and normalize MNIST
#'   mnist = dataset_mnist()
#'   x_train <- array_reshape(
#'     mnist$train$x, c(dim(mnist$train$x)[1], 784)
#'   )
#'   x_train <- x_train / 255.0
#'   x_test <- array_reshape(
#'     mnist$test$x, c(dim(mnist$test$x)[1], 784)
#'   )
#'   x_test <- x_test / 255.0
#'
#'   # Autoencoder with layers: 784-256-36-256-784
#'   learner <- autoencoder(c(256, 36), "binary_crossentropy")
#'   train(
#'     learner,
#'     x_train,
#'     epochs = 1,
#'     optimizer = "rmsprop",
#'     batch_size = 64,
#'     validation_data = x_test,
#'     metrics = list("binary_accuracy")
#'   )
#' }
#' }
#' @seealso `\link{autoencoder}`
#' @export
train.ruta_autoencoder <- function(
  learner,
  data,
  validation_data = NULL,
  metrics = NULL,
  epochs = 20,
  optimizer = "rmsprop",
  ...) {
  learner <- configure(learner, dim(data)[-1])
  loss_f <- learner$keras_loss

  if (is.function(loss_f)) {
    keras::compile(
      learner$models$autoencoder,
      optimizer = optimizer,
      loss = loss_f,
      metrics = metrics
    )
  } else {
    keras::compile(
      learner$models$autoencoder,
      optimizer = optimizer,
      loss = loss_f$losses,
      loss_weights = loss_f$loss_weights,
      metrics = metrics
    )
  }

  if (!is.null(validation_data)) {
    validation_data <- list(validation_data, validation_data)
  }

  if (is.null(learner$filter)) {
    keras::fit(
      learner$models$autoencoder,
      x = data,
      y = data,
      epochs = epochs,
      validation_data = validation_data,
      ...
    )
  } else {
    bsize <- list(...)$batch_size

    if (is.null(bsize)) bsize <- 32

    # Remove batch_size from dots parameters
    (function(..., batch_size = NULL)
    keras::fit_generator(
      learner$models$autoencoder,
      to_keras(learner$filter, data, bsize),
      steps_per_epoch = ceiling(dim(data)[1] / bsize),
      epochs = epochs,
      validation_data = validation_data,
      ...
    ))(...)
  }

  invisible(learner)
}

#' Automatically compute an encoding of a data matrix
#'
#' Trains an autoencoder adapted to the data and extracts its encoding for the
#'   same data matrix.
#' @param data Numeric matrix to be encoded
#' @param dim Number of variables to be used in the encoding
#' @param activation Activation type to be used in the encoding layer. Some available
#'   activations are `"tanh"`, `"sigmoid"`, `"relu"`, `"elu"` and `"selu"`
#' @param type Type of autoencoder to use: `"basic"`, `"sparse"`, `"contractive"`,
#'   `"denoising"`, `"robust"` or `"variational"`
#' @param epochs Number of times the data will traverse the autoencoder to update its
#'   weights
#' @return Matrix containing the encodings
#'
#' @examples
#' inputs <- as.matrix(iris[, 1:4])
#'
#' \donttest{
#' if (interactive() && keras::is_keras_available()) {
#'   # Train a basic autoencoder and generate a 2-variable encoding
#'   encoded <- autoencode(inputs, 2)
#'
#'   # Train a contractive autoencoder with tanh activation
#'   encoded <- autoencode(inputs, 2, type = "contractive", activation = "tanh")
#' }
#' }
#' @seealso `\link{autoencoder}`
#' @export
autoencode <- function(data, dim, type = "basic", activation = "linear", epochs = 20) {
  autoencoder_f <- switch(tolower(type),
                          basic = autoencoder,
                          sparse = autoencoder_sparse,
                          contractive = autoencoder_contractive,
                          denoising = autoencoder_denoising,
                          robust = autoencoder_robust,
                          variational = autoencoder_variational,
                          stop("The requested type of autoencoder does not exist"))

  autoencoder_f(input() + dense(dim, activation = activation) + output()) |>
    train(data, epochs = epochs) |>
    encode(data)
}

#' Retrieve encoding of data
#'
#' Extracts the encoding calculated by a trained autoencoder for the specified
#' data.
#' @param learner Trained autoencoder model
#' @param data data.frame to be encoded
#' @return Matrix containing the encodings
#' @seealso \code{\link{decode}}, \code{\link{reconstruct}}
#' @export
encode <- function(learner, data) {
  stopifnot(is_trained(learner))

  learner$models$encoder$predict(data)
}

#' Retrieve decoding of encoded data
#'
#' Extracts the decodification calculated by a trained autoencoder for the specified
#' data.
#' @param learner Trained autoencoder model
#' @param data data.frame to be decoded
#' @return Matrix containing the decodifications
#' @seealso \code{\link{encode}}, \code{\link{reconstruct}}
#' @export
decode <- function(learner, data) {
  stopifnot(is_trained(learner))

  learner$models$decoder$predict(data)
}


#' Retrieve reconstructions for input data
#'
#' Extracts the reconstructions calculated by a trained autoencoder for the specified
#' input data after encoding and decoding. `predict` is an alias for `reconstruct`.
#' @param learner Trained autoencoder model
#' @param object Trained autoencoder model
#' @param data data.frame to be passed through the network
#' @return Matrix containing the reconstructions
#' @seealso \code{\link{encode}}, \code{\link{decode}}
#' @export
reconstruct <- function(learner, data) {
  stopifnot(is_trained(learner))

  learner$models$autoencoder$predict(data)
}

#' @rdname reconstruct
#' @param ... Rest of parameters, unused
#' @export
predict.ruta_autoencoder <- function(object, ...) reconstruct(object, ...)
