#' OpenEO client class
#'
#' A R6Class that interacts with an openEO-conformant backend.
#'
#' @importFrom R6 R6Class
#' @import httr
#' @import magrittr
#' @import jsonlite
#' @importFrom raster extent
#' @importFrom gdalUtils gdalsrsinfo
#' @importFrom lubridate as_datetime
#' @export
OpenEOClient <- R6Class(
  "OpenEOClient",
  # public ----
  public = list(
    # attributes ====
    disableAuth = FALSE,
    general_auth_type = "bearer",
    user_id = NULL,
    
    is_rserver = FALSE,
    api.version = "0.0.2",
    
    products = list(),
    processes = list(),

    # functions ====
    initialize = function() {

    },

    connect = function(url) {
      if (!missing(url)) {
        if (endsWith(url,"/")) {
          url = substr(url,1,nchar(url)-1)
        }
        private$host = url
        # cat(paste("Registered '",url,"' as host","\n",sep=""))
        cat("Registered host\n")
        invisible(self)
      } else {
        stop("Host-URL is missing")
      }

    },
    capabilities = function() {
      endpoint = "capabilities"
      
      private$stopIfNotConnected()
      
      capabilities = private$GET(endpoint = endpoint,authorized = FALSE)
      
      return(capabilities)
    },
    services = function() {
      endpoint = "capabilities/services"
      
      private$stopIfNotConnected()
      
      services = private$GET(endpoint, authorized = FALSE)
      return(services)
    },
    output_formats = function() {
      endpoint = "capabilities/output_formats"
      formats = private$GET(endpoint,authorized = FALSE)
      
      return(formats)
    },
    udf_runtimes = function() {
      endpoint = "udf_runtimes"
      
      return(private$GET(endpoint = endpoint,
                         authorized = FALSE))
    },
    
    register = function(user=NULL,password) {
      #currently this will be used for GEE only
      endpoint = "auth/register"
      
      if (!private$isConnected()) {
        stop("No host selected")
      }
      
      
      private$password = password
      
      #function(endpoint,authorized=FALSE,data,encodeType = "json",query = list(), raw=FALSE,...) {
      res = private$POST(endpoint=endpoint,
                data = list(password=password),
                authorized = FALSE)

          
      private$user = res$user_id
      return(private$user)
      
    },

    login = function(user, password, auth_type="basic") {
      endpoint = "auth/login"

      if (missing(user) || missing(password)) {
        stop("Username or password is missing.")
      }
      if (!private$isConnected()) {
        stop("No host selected")
      }
      private$user = user
      private$password = password

      url = paste(private$host, endpoint, sep="/")
      res = GET(url=url,
                 config = authenticate(user=user,
                                       password = password,
                                       type = auth_type)
      )

      if (res$status_code == 200) {
        cont = content(res,type="application/json")

        private$login_token = cont$token
        self$user_id = cont$user_id

        cat("Login successful." )
        invisible(self)
      } else {
        stop("Login failed.")
      }
    },
    # list functions ####
    listData = function() {
      
      
      if (self$is_rserver) {
        endpoint = "data/"
      } else {
        endpoint = "data"
      }
      
      listOfProducts = private$GET(endpoint=endpoint,type="application/json")
      table = tibble(product_id = character(),
                     description = character(),
                     source = character())
      for (index in 1: length(listOfProducts)) {
        product = listOfProducts[[index]]
        
        product_id = product$product_id
        if ("description" %in% names(product)) {
          description = product$description
        } else {
          description = NA
        }
        
        if ("source" %in% names(product)) {
          source = product$source
        } else {
          source = NA
        }
        
        
        table = table %>% add_row(product_id = product_id,
                                  description = description,
                                  source = source)
      }
      
      return(table)

    },
    listProcesses = function() {
      
      if (self$is_rserver) {
        endpoint = "processes/"
      } else {
        endpoint = "processes"
      }
      
      listOfProcesses = private$GET(endpoint,type="application/json")
      
      table = tibble(process_id = character(),
                     description = character())
      
      for (index in 1:length(listOfProcesses)) {
        process = listOfProcesses[[index]]
        table = table %>% add_row(process_id = process$process_id,
                                  description = process$description)
      }
      
      return(table)
    },
    listJobs = function() {
      endpoint = paste("users",self$user_id,"jobs",sep="/")
      listOfJobs = private$GET(endpoint,authorized=TRUE,type="application/json")
      # list to tibble
      table = tibble(job_id=character(),
                     status=character(),
                     submitted=.POSIXct(integer(0)),
                     updated=.POSIXct(integer(0)),
                     consumed_credits=integer(0))
      
      for (index in 1:length(listOfJobs)) {
        job = listOfJobs[[index]]
        table= add_row(table,
                job_id=job$job_id,
                status = job$status,
                submitted = as_datetime(job$submitted),
                updated = as_datetime(job$updated),
                consumed_credits = job$consumed_credits)
      }
      
      return(table)
    },
    
    listGraphs = function() {
      endpoint = paste("users",self$user_id,"process_graphs",sep="/")
      listOfGraphIds = private$GET(endpoint, authorized = TRUE)
      
      return(listOfGraphIds)
    },
    listServices = function() {
      endpoint = paste("users",self$user_id,"services",sep="/")
      listOfServices = private$GET(endpoint,authorized = TRUE ,type="application/json")
      table = tibble(service_id=character(),
                     service_type=character(),
                     service_args=list(),
                     job_id=character(),
                     service_url=character())
      
      for (index in 1:length(listOfServices)) {
        service = listOfServices[[index]]
        
        if (!is.null(service$service_args) && length(service$service_args) == 0) {
          service$service_args <- NULL
        }
        table= do.call("add_row",append(list(.data=table),service))
      }
      
      return(table)
    },
    
    listUserFiles = function() {
      endpoint = paste("users",self$user_id,"files",sep="/")
      files = private$GET(endpoint,TRUE,type="application/json")
      
      if (is.null(files) || length(files) == 0) {
        message("The user workspace at this host is empty.")
        return(invisible(files))
      }
      
      files = tibble(files) %>% rowwise() %>% summarise(name=files$name, size=files$size)
      
      return(files)
    },
    # describe functions ####
    describeProcess = function(pid) {
      endpoint = paste("processes",pid,sep="/")
      
      info = private$GET(endpoint = endpoint,authorized = FALSE, type="application/json",auto_unbox=TRUE)
      
      # info is currently a list 
      # make a class of it and define print
      class(info) <- "ProcessInfo"

      return(info)
    },
    describeProduct = function(pid) {
      endpoint = paste("data",pid,sep="/")
      
      info = private$GET(endpoint = endpoint,authorized = FALSE, type="application/json",auto_unbox=TRUE)

      tryCatch({
        info = private$modifyProductList(info)
        class(info) = "openeo_product"
      },
      error = function(e) {
        warning(as.character(e))
      },
      finally = return(info))
    },
    describeJob = function(job_id) {
      endpoint = paste("jobs",job_id,sep="/")
      
      info = private$GET(endpoint = endpoint,authorized = TRUE, type="application/json",auto_unbox=TRUE)
      table = tibble(job_id = info$job_id,
                     status = info$status,
                     process_graph = list(info$process_graph),
                     output = list(info$output),
                     submitted = as_datetime(info$submitted),
                     updated = as_datetime(info$updated),
                     user_id = info$user_id,
                     consumed_credits = info$consumed_credits)
      
      return(table)
    },
    describeGraph = function(graph_id, user_id = NULL) {
      if (is.null(graph_id)) {
        stop("No graph id specified. Cannot fetch unknown graph.")
      }
      
      if (is.null(user_id)) {
        user_id = self$user_id #or "me"
      }
      
      enpoint = paste("users", user_id, "process_graphs", graph_id, sep="/")
      graph = private$GET(endpoint, authorized = TRUE, type="application/json",auto_unbox=TRUE)
      
      return(graph)
    },
    describeService = function(service_id) {
      if (is.null(service_id)) {
        stop("No service id specified.")
      }
      endpoint = paste("services",service_id,sep="/")
      
      return(private$GET(endpoint,authorized = TRUE))
    },
    describeUdfType = function(language, udf_type) {
      if (is.null(language) || is.null(udf_type)) {
        stop("Missing parameter language or udf_type")
      }
      
      endpoint = paste("udf_runtimes",language,udf_type,sep="/")
      
      msg = private$GET(endpoint = endpoint,
                        authorized = FALSE)
      return(msg)
    },
    
    replaceGraph = function(graph_id, graph) {
      if (is.null(graph_id)) {
        stop("Cannot replace unknown graph. If you want to store the graph, use 'storeGraph' instead")
      }
      if (is.null(graph)) {
        stop("Cannot replace graph with 'NULL'")
      }
      if (!is.list(graph) || is.null(graph)) {
        stop("The graph information is missing or not a list")
      }
      endpoint = paste("users",self$user_id,"process_graphs",graph_id,sep="/")
      message = private$PUT(endpoint = endpoint, 
                              authorized = TRUE, 
                              data = graph,
                              encodeType = "json")
      
      return(message) #in principle a void function
      
    },
    
    uploadUserFile = function(file.path,target,encode="raw",mime="application/octet-stream") {
      target = URLencode(target,reserved = TRUE)
      target = gsub("\\.","%2E",target)

      if (is.null(self$user_id)) {
        stop("User id is not set. Either login or set the id manually.")
      }

      endpoint = paste("users",self$user_id,"files",target,sep="/")
      
      message = private$PUT(endpoint= endpoint,authorized = TRUE, data=upload_file(file.path,type=mime),encodeType = encode)

      return(message)
    },
    downloadUserFile = function(src, dst=NULL) {
      if (!is.character(src)) {
        stop("Cannot download file with a source statement that is no character")
      } else {
        src = .urlHardEncode(src)
      }
      
      if (is.null(dst)) {
        dst = tempfile()
      }
      
      endpoint = paste("users",self$user_id,"files",src,sep="/")
      file_connection = file(dst,open="wb")
      writeBin(object=private$GET(endpoint,authorized = TRUE,as = "raw"),con = file_connection)
      close(file_connection,type="wb")
      
      return(dst)
    },
    storeGraph = function(graph) {
      endpoint = paste("users",self$user_id,"process_graphs",sep="/")
      
      if (!is.list(graph) || is.null(graph)) {
        stop("The graph information is missing or not a list")
      }
      
      okMessage = private$POST(endpoint=endpoint,
                               authorized = TRUE,
                               data=graph)
      
      message("Graph was sucessfully stored on the backend.")
      return(okMessage$process_graph_id)
    },
    storeJob = function(task=NULL,graph_id=NULL,format, ...) {

      if (self$is_rserver) {
        endpoint = paste("jobs/",sep="/")
      } else {
        endpoint = paste("jobs",sep="/")
      }
      if (is.null(format)) {
        # format = self$output_formats()$default
      }
      
      output = list(...)
      output = append(output, list(format=format))
      
      if (!is.null(task)) {
        if (is.list(task)) {
          job = list(process_graph=task,output = output)
        } else {
          stop("Parameter task is not a task object. Awaiting a list.")
        }
      } else if (! is.null(graph_id)) {
        job = list(process_graph=graph_id,output = output)
      } else {
        stop("No process graph was defined. Please provide either a process graph id or a process graph description.")
      }

      #endpoint,authorized=FALSE,data,encodeType = "json",query = list(),...
      okMessage = private$POST(endpoint=endpoint,
                               authorized = TRUE,
                               data=job)
      
      message("Job was sucessfully registered on the backend.")
      return(okMessage$job_id)
    },
    modifyJob = function(job_id,...) {
      if (is.null(job_id)) {
        stop("No job i was specified.")
      }
      endpoint = paste("jobs",job_id,sep="/")
      
      updateables = list(...)
      
      patch = list()
      graph = NULL
      if ("graph_id" %in% names(updateables)) {
        graph = updateables$graph_id
        updateables$graph_id = NULL
      } else if ("task" %in% names(updateables)) {
        graph = updateables$task
        updateables$task = NULL
      }
      if (!is.null(graph)) {
        patch = append(patch,process_graph = graph)
      }
      
      if (length(updateables) > 0) {
        patch = append(patch, output=updateables)
      }
      
      #endpoint, authorized=FALSE, data=NULL, encodeType = NULL, ...
      return(private$PATCH(endpoint = endpoint,
                    authorized = TRUE,
                    encodeType = "json",
                    data=patch))
      
    },
    execute = function (task=NULL,graph_id=NULL,output_file=NULL,format=NULL, ...) {
      # former sync evaluation
      if (self$is_rserver) {
        endpoint = paste("execute/",sep="/")
      } else {
        endpoint = paste("execute",sep="/")
      }
      if (is.null(format)) {
        format = self$output_formats()$default
      }
      
      output = list(...)
      output = append(output, list(format=format))
      if (!is.null(task)) {
        if (is.list(task)) {
          job = list(process_graph=task,output = output)
        } else {
          stop("Parameter task is not a task object. Awaiting a list.")
        }
      } else if (! is.null(graph_id)) {
        job = list(process_graph=graph_id,output = output)
      } else {
        stop("No process graph was defined. Please provide either a process graph id or a process graph description.")
      }
      
      header = list()
      header = private$addAuthorization(header)
      
      
      res = private$POST(endpoint,
                         authorized = TRUE, 
                         data=job,
                         encodeType = "json",
                         raw=TRUE)
      
      if (!is.null(output_file)) {
        tryCatch(
          {
            message("Task result was sucessfully stored.")
            writeBin(content(res,"raw"),output_file)
          },
          error = function(err) {
            stop(err)
          }
        )
        
        return(output_file)
        # drivers = gdalDrivers()
        # ogr_drivers = ogrDrivers()
        # 
        # allowedGDALFormats = drivers[drivers$create,"name"]
        # allowedOGRFormats = ogr_drivers[ogr_drivers$write, "name"]
        # 
        # if (format %in% allowedGDALFormats) {
        #   suppressMessages(
        #     tryCatch ({
        #       return(raster(output_file))
        #     },error = function(err) {
        #       return(readOGR(output_file))
        #     })
        #   )
        # } else {
        #   return(readOGR(output_file))
        # }
        
      } else {
        return(content(res,"raw"))
      }

      
    },
    queue = function(job_id) {
      if (is.null(job_id)) {
        stop("No job id specified.")
      }
      endpoint = paste("jobs",job_id,"queue",sep="/")
      
      success = private$PATCH(endpoint = endpoint, authorized = TRUE)
      message(paste("Job '",job_id,"' has been successfully queued for evaluation.",sep=""))
      
      invisible(self)
    },
    results = function(job_id, format = NULL) {
      if (is.null(job_id)) {
        stop("No job id specified.")
      }
      
      endpoint = paste("jobs",job_id,"download",sep="/")
      supportedFormats = names(self$output_formats()$formats)
      if (!is.null(format) && format %in% supportedFormats) {
        return(private$GET(endpoint = endpoint,
                             authorized = TRUE,
                             query=list(
                               format=format
                             )))
      } else {
        return(private$GET(endpoint = endpoint,
                              authorized = TRUE))
      }
      
    },
    pause = function(job_id) {
      if (is.null(job_id)) {
        stop("No job id specified.")
      }
      endpoint = paste("jobs",job_id,"pause",sep="/")
      
      success = private$PATCH(endpoint = endpoint, authorized = TRUE)
      message(paste("Job '",job_id,"' has been successfully paused.",sep=""))
      return(success)
    },
    cancel = function(job_id) {
      if (is.null(job_id)) {
        stop("No job id specified.")
      }
      endpoint = paste("jobs",job_id,"cancel",sep="/")
      
      success = private$PATCH(endpoint = endpoint, authorized = TRUE)
      message(paste("Job '",job_id,"' has been successfully canceled.",sep=""))
      return(success)
    },
    
    deleteUserFile = function (src) {
      
      if (is.character(src)) {
        src = .urlHardEncode(src)
      } else {
        stop("Cannot interprete parameter 'src' during delete request")
      }
      endpoint = paste("users",self$user_id,"files",src,sep="/")
      
      return(private$DELETE(endpoint = endpoint, authorized = TRUE))
    }, 
    deleteGraph = function(graph_id) {
      endpoint = paste("users",self$user_id,"process_graphs",graph_id,sep="/")
      
      return(private$DELETE(endpoint = endpoint, authorized = TRUE))
    },
    deleteService = function(service_id) {
      endpoint = paste("services",service_id,sep="")
      
      msg = private$DELETE(endpoint = endpoint,
                     authorized = TRUE)
      message("Service '",service_id,"' successfully deactivated")
      invisibile(msg)
    },
    getUserCredits = function() {
      endpoint = paste("users",self$user_id,"credits",sep="/")
      
      return(private$GET(endpoint,authorized = TRUE))
    },
    createService = function(job_id, service_type, ...) {
      if (is.null(job_id)) {
        stop("Cannot create service. job_id is missing.")
      }
      if (is.null(service_type)) {
        stop("No service_type specified.")
      }
      if (self$is_rserver) {
        endpoint = "services/"
      } else {
        endpoint = "services"
      }
    
      service_args = list(...)
      
      service_request_object = list(
        job_id = job_id,
        service_type = service_type,
        service_args = service_args
      )
      
      response = private$POST(endpoint,
                   authorized = TRUE, 
                   data = service_request_object, 
                   encodeType = "json")
      
      message("Service was successfully created.")
      return(response)
      
    },
    modifyService = function() {
      
    },
    getProcessGraphBuilder = function() {
      
      if (is.null(private$graph_builder)) {
        private$graph_builder = ProcessGraphBuilder$new(self)
      }
      
      return(private$graph_builder)
    }

  ),
  # private ----
  private = list(
    # attributes ====
    login_token = NULL,
    user = NULL,
    password = NULL,
    host = NULL,
    graph_builder=NULL,
    
    # functions ====
    isConnected = function() {
      return(!is.null(private$host))
    },

    isLoggedIn = function() {

      hasToken = !is.null(private$login_token)
      return(hasToken || self$disableAuth)
    },
    checkLogin = function() {
      if (!private$isLoggedIn()) {
        stop("You are not logged in.")
      }
    },
    GET = function(endpoint,authorized=FALSE,query = list(), ...) {
      url = paste(private$host,endpoint, sep ="/")

      if (authorized && !self$disableAuth) {
        response = GET(url=url, config=private$addAuthorization(),query=query)
      } else {
        response = GET(url=url,query=query)
      }


      if (response$status_code %in% c(200)) {
        info = content(response, ...)
        return(info)

      } else if (response$status_code %in% c(404)) {
        stop(paste("Cannot find or access endpoint ","'",endpoint,"'",sep=""))
      } else {
        stop(response$message)
      }
    },
    DELETE = function(endpoint,authorized=FALSE,...) {
      url = paste(private$host,endpoint,sep="/")
      
      header = list()
      if (authorized && !self$disableAuth) {
        header = private$addAuthorization(header)
      }
      
      response = DELETE(url=url, config = header, ...)
      
      message = content(response)
      success = response$status_code %in% c(200,202,204)
      if (success) {
        tmp = lapply(message, function(elem) {
          message(elem)
        })
      } else {
        tmp = lapply(message, function(elem) {
          warning(elem)
        })
      }
      
      return(success)
    },
    POST = function(endpoint,authorized=FALSE,data,encodeType = "json",query = list(), raw=FALSE,...) {
      url = paste(private$host,endpoint,sep="/")
      if (!is.list(query)) {
        stop("Query parameters are no list of key-value-pairs")
      }
      
      if (is.list(data)) {
        
        header = list()
        if (authorized && !self$disableAuth) {
          header = private$addAuthorization(header)
        }
        
        # create json and prepare to send graph as post body
        
        response=POST(
          url= url,
          config = header,
          query = query,
          body = data,
          encode = encodeType
        )
        
        success = response$status_code %in% c(200,202,204)
        if (success) {
          if (raw) {
            return(response)
          } else {
            okMessage = content(response,"parsed","application/json")
            return(okMessage)
          }
        } else {
          error = content(response,"text","application/json")
          stop(error)
        }
      } else {
        stop("Cannot interprete data - data is no list that can be transformed into json")
      }
    },
    PUT = function(endpoint, authorized=FALSE, data, encodeType = NULL, ...) {
      url = paste(private$host,endpoint,sep="/")
      
      header = list()
      if (authorized && !self$disableAuth) {
        header = private$addAuthorization(header)
      }
      
      params = list(url=url, 
                    config = header, 
                    body=data)
      if (!is.null(encodeType)) {
        params = append(params, list(encode = encodeType))
      }
      response = do.call("PUT", args = params)
      
      success = response$status_code %in% c(200,202,204)
      if (success) {
        okMessage = content(response,"parsed","application/json")
        return(okMessage)
      } else {
        error = content(response,"text","application/json")
        stop(error)
      }
    },
    PATCH = function(endpoint, authorized=FALSE, data=NULL, encodeType = NULL, ...) {
      url = paste(private$host,endpoint,sep="/")
      
      header = list()
      if (authorized && !self$disableAuth) {
        header = private$addAuthorization(header)
      }
      
      params = list(url=url, 
                    config = header)
      
      if (!is.null(data)) {
        params = append(params, list(body = data))
      }
      
      if (!is.null(encodeType)) {
        params = append(params, list(encode = encodeType))
      }
      response = do.call("PATCH", args = params)
      
      success = response$status_code %in% c(200,202,204)
      if (success) {
        okMessage = content(response,"parsed","application/json")
        return(okMessage)
      } else {
        error = content(response,"text","application/json")
        stop(error)
      }
    },
    modifyProductList = function(product) {
      if (is.list(product) && any(c("collection_id","product_id") %in% names(product))) {
        if ("extent" %in% names(product)) {
          e = product$extent
  
          ext = extent(e$left,e$right,e$bottom,e$top)
          product$extent = ext
          
          if ("srs" %in% names(e)) {
            product$crs = gdalsrsinfo(e$srs, as.CRS = TRUE)
          }
        }
        
        if ("time" %in% names(product)) {
          if ("from" %in% names(product$time)) {
            product$time$from = as_datetime(product$time$from)
          }
          if ("to" %in% names(product$time)) {
            product$time$to = as_datetime(product$time$to)
          }
        }

        return(product)

      } else {
        stop("Object that is modified is not the list result of product.")
      }
    },
    # returns the header list and adds Authorization
    addAuthorization = function (header) {
      if (missing(header)) {
        header = list()
      }

      if (self$general_auth_type == "bearer") {
        header = append(header,add_headers(
          Authorization=paste("Bearer",private$login_token, sep =" ")
        ))
      } else {
        header = append(header,authenticate(private$user,private$password,type = self$general_auth_type))
      }

      return(header)
    },
    stopIfNotConnected = function() {
      if (!private$isConnected()) {
        stop("No host selected")
      }
    }
    


  )

)

# statics -----
.urlHardEncode=function(text) {
  text = URLencode(text)
  text = gsub("\\/","%2F",text)
  text = gsub("\\.","%2E",text)
  return(text)
}

#' @export
print.openeo_product = function(x, ...) {
  return(str(x))
}



