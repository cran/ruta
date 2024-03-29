% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/autoencoder.R
\name{autoencoder}
\alias{autoencoder}
\title{Create an autoencoder learner}
\usage{
autoencoder(network, loss = "mean_squared_error")
}
\arguments{
\item{network}{Layer construct of class \code{"ruta_network"} or coercible}

\item{loss}{A \code{"ruta_loss"} object or a character string specifying a loss function}
}
\value{
A construct of class \code{"ruta_autoencoder"}
}
\description{
Represents a generic autoencoder network.
}
\examples{

# Basic autoencoder with a network of [input]-256-36-256-[input] and
# no nonlinearities
autoencoder(c(256, 36), loss = "binary_crossentropy")

# Customizing the activation functions in the same network
network <-
  input() +
  dense(256, "relu") +
  dense(36, "tanh") +
  dense(256, "relu") +
  output("sigmoid")

learner <- autoencoder(
  network,
  loss = "binary_crossentropy"
)

}
\references{
\itemize{
\item \href{https://arxiv.org/abs/1801.01586}{A practical tutorial on autoencoders for nonlinear feature fusion}
}
}
\seealso{
\code{\link{train.ruta_autoencoder}}

Other autoencoder variants: 
\code{\link{autoencoder_contractive}()},
\code{\link{autoencoder_denoising}()},
\code{\link{autoencoder_robust}()},
\code{\link{autoencoder_sparse}()},
\code{\link{autoencoder_variational}()}
}
\concept{autoencoder variants}
