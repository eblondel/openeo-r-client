% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/wrapper-functions.R
\name{defineJob}
\alias{defineJob}
\title{Creates a job on the back-end from a prepared task}
\usage{
defineJob(con, task = NULL, graph_id = NULL, format = NULL, ...)
}
\arguments{
\item{con}{connected and authenticated openeo client}

\item{task}{A Process or chained processes to a Task}

\item{graph_id}{The id of an already stored process graph on the same back-end}

\item{format}{The inteded format of the data to be returned}

\item{...}{additional configuration parameter for output generation}
}
\value{
the id of the job
}
\description{
This function shall be called after the user defined a task for the back-end to create a job on the
back-end. Therefore the user sends the task (process graph) and the optional output specifications like
format and additional creation parameter by '...'. Afterwards ths user can decide to either execute the
job asynchronous or they can create a service from it.
}
