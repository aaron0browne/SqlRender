# @file HelperFunctions.R
#
# Copyright 2014 Observational Health Data Sciences and Informatics
#
# This file is part of SqlRender
# 
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
#     http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# @author Observational Health Data Sciences and Informatics
# @author Martijn Schuemie
# @author Marc Suchard

#' Reads a SQL file
#'
#' @description
#' \code{readSql} loads SQL from a file
#'
#' @details
#' \code{readSql} loads SQL from a file
#' 
#' @param sourceFile               The source SQL file
#' 
#' @return
#' Returns a string containing the SQL.
#' 
#' @examples \dontrun{
#' readSql("myParamStatement.sql")
#' }
#' @export
readSql <- function(sourceFile) {
  readChar(sourceFile, file.info(sourceFile)$size)  
}

#' Write SQL to a SQL (text) file
#'
#' @description
#' \code{writeSql} writes SQL to a file
#'
#' @details
#' \code{writeSql} writes SQL to a file
#' 
#' @param sql                     A string containing the sql
#' @param targetFile              The target SQL file
#' 
#' @examples \dontrun{
#' sql <- "SELECT * FROM @@table_name"
#' writeSql(sql,"myParamStatement.sql")
#' }
#' @export
writeSql <- function(sql, targetFile) {
  sink(targetFile)
  sql <- gsub("\r","",sql) #outputting to file duplicates carriage returns, so remove them beforehand (still got newline)
  cat(sql)
  sink()
}


#' Render a SQL file
#'
#' @description
#' \code{renderSqlFile} Renders SQL code in a file based on parameterized SQL and parameter values, and writes it to another file.
#'
#' @details
#' This function takes parameterized SQL and a list of parameter values and renders the SQL that can be 
#' send to the server. Parameterization syntax:
#' \describe{
#'   \item{@@parameterName}{Parameters are indicated using a @@ prefix, and are replaced with the actual
#'   values provided in the renderSql call.}
#'   \item{\{DEFAULT @@parameterName = parameterValue\}}{Default values for parameters can be defined using 
#'   curly and the DEFAULT keyword.}
#'   \item{\{if\}?\{then\}:\{else\}}{The if-then-else pattern is used to turn on or off blocks of SQL code.}
#' }
#' 
#' 
#' @param sourceFile               The source SQL file
#' @param targetFile               The target SQL file
#' @param ...                   Parameter values
#'
#' @examples \dontrun{
#' renderSqlFile("myParamStatement.sql","myRenderedStatement.sql",a="myTable")
#' }
#' @export
renderSqlFile <- function(sourceFile, targetFile, ...) {
  sql <- readSql(sourceFile)  
  sql <- renderSql(sql,...)$sql
  writeSql(sql,targetFile)
}

#' Translate a SQL file
#'
#' @description
#' This function takes SQL and translates it to a different dialect.
#'
#' @details
#' This function takes SQL and translates it to a different dialect. 
#' 
#' @param sourceFile               The source SQL file
#' @param targetFile               The target SQL file
#' @param sourceDialect     The source dialect. Currently, only "sql server" for Microsoft SQL Server is supported
#' @param targetDialect  	The target dialect. Currently "oracle", "postgresql", and "redshift" are supported
#'
#' @examples \dontrun{
#' translateSqlFile("myRenderedStatement.sql","myTranslatedStatement.sql",targetDialect="postgresql")
#' }
#' @export
translateSqlFile <- function(sourceFile, targetFile, sourceDialect = "sql server", targetDialect = "oracle") {
  sql <- readSql(sourceFile)
  sql <- translateSql(sql,sourceDialect,targetDialect)$sql
  writeSql(sql,targetFile)
}

#' Load, render, and translate a SQL file in a package
#'
#' @description
#' \code{loadRenderTranslateSql} Loads a SQL file contained in a package, renders it and translates it to the specified dialect
#'
#' @details
#' This function looks for a SQL file with the specified name in the inst/sql/<dbms> folder of the specified package. 
#' If it doesn't find it in that folder, it will try and load the file from the inst/sql/sql_server folder and use the
#' \code{translateSql} function to translate it to the requested dialect. It will subsequently call the \code{renderSql}
#' function with any of the additional specified parameters.
#' 
#' 
#' @param sqlFilename           The source SQL file
#' @param packageName           The name of the package that contains the SQL file
#' @param dbms                  The target dialect. Currently "sql server", "oracle", "postgres", and "redshift" are supported
#' @param ...                   Parameter values used for \code{renderSql}
#'
#' @return
#' Returns a string containing the rendered SQL.
#' @examples \dontrun{
#'   renderedSql <- loadRenderTranslateSql("CohortMethod.sql",
#'                                          packageName = "CohortMethod",
#'                                          dbms = connectionDetails$dbms,
#'                                          CDM_schema = "cdmSchema")
#' }
#' @export
loadRenderTranslateSql <- function(sqlFilename, packageName, dbms="sql server", ...){
  pathToSql <- system.file(paste("sql/",gsub(" ","_",dbms),sep=""), sqlFilename, package=packageName)
  mustTranslate <- !file.exists(pathToSql)
  if (mustTranslate) # If DBMS-specific code does not exists, load SQL Server code and translate after rendering
    pathToSql <- system.file(paste("sql/","sql_server",sep=""), sqlFilename, package=packageName)      
  parameterizedSql <- readChar(pathToSql,file.info(pathToSql)$size)  
  
  renderedSql <- renderSql(parameterizedSql[1], ...)$sql
  
  if (mustTranslate)
    renderedSql <- translateSql(renderedSql, "sql server", dbms)$sql
  
  renderedSql
}

trim <- function(string){
  gsub("(^ +)|( +$)", "",  string)
}

snakeCaseToCamelCase <- function(string){
  string <- tolower(string)
  for(letter in letters){
    string = gsub(paste("_",letter,sep=""),toupper(letter),string)
  }
  string
}

#' Create an R wrapper for SQL
#'
#' @description
#' \code{createRWrapperForSql} creates an R wrapper for a parameterized SQL file. The created R script
#' file will contain a single function, that executes the SQL, and accepts the same parameters as
#' specified in the SQL.
#'
#' @details
#' This function reads the declarations of defaults in the parameterized SQL file, and creates an R 
#' function that exposes the parameters. It uses the \code{loadRenderTranslateSql} function, and 
#' assumes the SQL will be used inside a package.
#' 
#' To use inside a package, the SQL file should be placed in the inst/sql/sql_server folder of the 
#' package.  
#' 
#' @param sqlFilename           The SQL file.
#' @param rFilename             The name of the R file to be generated. Defaults to the name of the 
#' SQL file with the extention reset to R.
#' @param packageName           The name of the package that will contains the SQL file.
#' @param createRoxygenTemplate If true, a template of Roxygen comments will be added.
#'
#' @examples \dontrun{
#'   #This will create a file called CohortMethod.R:
#'   createRWrapperForSql("CohortMethod.sql",packageName = "CohortMethod")
#' }
#' @export
createRWrapperForSql <- function(sqlFilename, 
                                 rFilename,
                                 packageName,
                                 createRoxygenTemplate = TRUE
){
  if (missing(rFilename)){
    periodIndex = which(strsplit(sqlFilename, "")[[1]]==".")
    if (length(periodIndex) == 0){
      rFilename = paste(sqlFilename,"R",sep=".")
    } else {
      periodIndex = periodIndex[length(periodIndex)] #pick last one
      rFilename = paste(substr(sqlFilename,1,periodIndex),"R",sep="")
    }
  }
  
  pathToSql <- system.file(paste("sql/","sql_server",sep=""), sqlFilename, package=packageName) 
  if (file.exists(pathToSql)){
    writeLines(paste("Reading SQL from package folder:",pathToSql))
    parameterizedSql <- readSql(pathToSql) 
  } else if (file.exists(sqlFilename)){
    writeLines(paste("Reading SQL from current folder:",file.path(getwd(),sqlFilename)))
    writeLines("Note: make sure the SQL file is placed in the /inst/sql/sql_server folder when building the package")
    parameterizedSql <- readSql(sqlFilename) 
  } else {
    stop("Could not find SQL file")
  }
  
  hits <- gregexpr("\\{DEFAULT @[^}]*\\}",parameterizedSql) 
  hits <- cbind(hits[[1]],attr(hits[[1]],"match.length"))
  f <- function(x) {
    x <- substr(parameterizedSql,x[1],x[1]+x[2])
    start = regexpr("@",x) + 1
    equalSign = regexpr("=",x)
    end = regexpr("\\}",x) - 1
    parameter <- trim(substr(x, start,equalSign-1))
    value <- trim(substr(x, equalSign+1,end))
    if (grepl(",",value) & substr(value,1,1) != "'")
      value <- paste("c(",value,")",sep="")
    if (substr(value,1,1) == "'" & substr(value,nchar(value),nchar(value)) == "'")
      value <- paste("\"",substr(value,2,nchar(value)-1),"\"",sep="")
    ccParameter = snakeCaseToCamelCase(parameter)
    c(parameter,ccParameter,value)
  }
  definitions <- t(apply(hits,1,FUN = f))
  
  lines <- c()
  if (createRoxygenTemplate){
    lines <- c(lines,"#' Todo: add title")  
    lines <- c(lines,"#'")    
    lines <- c(lines,"#' @description")  
    lines <- c(lines,"#' Todo: add description")  
    lines <- c(lines,"#'")  
    lines <- c(lines,"#' @details")  
    lines <- c(lines,"#' Todo: add details")  
    lines <- c(lines,"#'") 
    lines <- c(lines,"#' @param connectionDetails\t\tAn R object of type \\code{ConnectionDetails} created using the function \\code{createConnectionDetails} in the \\code{DatabaseConnector} package.")  
    for (i in 1:nrow(definitions)){
      lines <- c(lines,paste("#' @param",definitions[i,2],"\t\t"))
    }
    lines <- c(lines,"#'")  
    lines <- c(lines,"#' @export")  
  }
  lines <- c(lines,paste(gsub(".sql","",sqlFilename)," <- function(connectionDetails,",sep=""))
  for (i in 1:nrow(definitions)){
    if (i == nrow(definitions))
      end = ") {"
    else
      end = ","
    lines <- c(lines,paste("                        ",definitions[i,2]," = ",definitions[i,3],end,sep=""))
  }
  lines <- c(lines,paste("  renderedSql <- loadRenderTranslateSql(\"",sqlFilename,"\",",sep=""))
  lines <- c(lines,paste("              packageName = \"",packageName,"\",",sep=""))
  lines <- c(lines,"              dbms = connectionDetails$dbms,")
  for (i in 1:nrow(definitions)){
    if (i == nrow(definitions))
      end = ")"
    else
      end = ","
    lines <- c(lines,paste("              ",definitions[i,1]," = ",definitions[i,2],end,sep=""))
  }
  lines <- c(lines,"  conn <- connect(connectionDetails)")  
  lines <- c(lines,"")  
  lines <- c(lines,"  writeLines(\"Executing multiple queries. This could take a while\")")  
  lines <- c(lines,"  executeSql(conn,renderedSql)")  
  lines <- c(lines,"  writeLines(\"Done\")") 
  lines <- c(lines,"")  
  lines <- c(lines,"  dummy <- dbDisconnect(conn)")  
  lines <- c(lines,"}") 
  writeLines(paste("Writing R function to:",rFilename))
  sink(rFilename)
  cat(paste(lines,collapse="\n"))
  sink()
}
