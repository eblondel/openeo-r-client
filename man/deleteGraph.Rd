% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/wrapper-functions.R
\name{deleteGraph}
\alias{deleteGraph}
\title{Deletes a previously stored process graph}
\usage{
deleteGraph(con, graph_id)
}
\arguments{
\item{con}{connected and authorized openeo client object}

\item{graph_id}{the id of the graph}
}
\description{
The function initiates the deletion of a process graph on the back-end. Only the owning user can delete
a graph. The graph also should not be part of any particular job.
}
