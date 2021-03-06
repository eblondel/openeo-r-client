% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/wrapper-functions.R
\name{describeCollection}
\alias{describeCollection}
\title{Describe a product}
\usage{
describeCollection(con, collection_id = NA)
}
\arguments{
\item{con}{Authentication object}

\item{collection_id}{id of a product/collection to be described}
}
\value{
a list of detailed information about a product/collection
}
\description{
Queries an openeo back-end and retrieves a detailed description about one or more collections offered by the back-end
}
