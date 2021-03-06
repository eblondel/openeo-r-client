% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/wrapper-functions.R
\name{describeUdfType}
\alias{describeUdfType}
\title{Gets detailed information about a particular udf type}
\usage{
describeUdfType(con, language, type)
}
\arguments{
\item{con}{connected and authenticated openeo client object}

\item{language}{the udf runtime identifier}

\item{type}{the udf type}
}
\value{
list with udf runtime type information
}
\description{
Queries the back-end for a particular runtime and time to retrieve information how the udf_type will work.
}
