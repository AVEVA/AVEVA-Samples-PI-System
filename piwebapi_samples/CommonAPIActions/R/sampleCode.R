context("TestRSample")

if (!require("pacman")) install.packages("pacman", repos = "https://cran.r-project.org", quiet = TRUE)
require("pacman", quietly = TRUE)
source("test_config.R")
p_load("httr", "jsonlite", "tcltk")

databaseName <- "OSIRDatabase"
categoryName <- "OSIRCategory"
templateName <- "OSIRTemplate"
attributeActiveName <- "OSIRAttributeActive"
attributeSinusoidName<- "OSIRAttributeSinusoid"
tagName <- "OSIRSampleTag"
attributeSampleTagName <- "OSIRAttributeSampleTag"
elementName <- "OSIRElement"

#Sample application UI
runPIWebAPISamples <- function(){
  dlg <- tktoplevel()
  ctrlFrame <- tkframe(dlg, borderwidth = 3)
  
  tkwm.title(dlg, "PIWeb.API Calls")
  
  lblStep1 = tklabel(dlg, width=100, justify="left", text="Step 1: Create the sandbox\nExecute the following Actions in order: Create Database, Create Category, Create Template and Create Element
                     \n\nStep 2: Write values to the tags\nExecute the following Actions: Write Single Value, Write Set of Values, Update Attribute Value
                     \n\nStep 3: Read the tags\nExecute the following Actions: Get Single Value, Get Set of Values, Reduce Payload with Selected Fields
                     \n\nStep 4: Perform advanced features\nExecute the following Actions: Batch Writes and Reads")
  
  tkpack(lblStep1,
         side = "right", expand = TRUE,
         ipadx = 5, ipady = 5, fill = "both") 
  
  tkpack(ctrlFrame, expand = TRUE, fill = "both")
  
  #Dialog form variables
  Name <- tclVar(defaultName)
  Password <- tclVar(defaultPassword)
  PIWebAPIUrl <- tclVar(defaultPIWebAPIUrl)
  AssetServer <- tclVar(defaultAssetServer)
  PIServer <- tclVar(defaultPIServer)
  authorization <- tclVar("Kerberos")
  
  Selection <- tclVar("Create AF OSIRDatabase Database")
  
  #Dialog form controls
  entry.Name <- tkentry(ctrlFrame,width="50", textvariable=Name)
  entry.Password <- tkentry(ctrlFrame, width="50", show="*", textvariable=Password)
  entry.PIWebAPIUrl <- tkentry(ctrlFrame,width="50", textvariable=PIWebAPIUrl)
  entry.AssetServer <- tkentry(ctrlFrame,width="50", textvariable=AssetServer)
  entry.PIServer <- tkentry(ctrlFrame,width="50", textvariable=PIServer)
  
  tkgrid(tklabel(ctrlFrame, text="PI Web API URL:"), sticky = "w")
  tkgrid(entry.PIWebAPIUrl, padx = 10, pady = 5)
  tkgrid(tklabel(ctrlFrame, text="Asset Server:"), sticky = "w")
  tkgrid(entry.AssetServer, padx = 10, pady = 5)
  tkgrid(tklabel(ctrlFrame, text="PI Server:"), sticky = "w")
  tkgrid(entry.PIServer, padx = 10, pady = 5)
  
  authorizationMethods <- c("Basic", "Kerberos")
  ctrlFrame$env$comboAuth <- ttkcombobox(ctrlFrame, width="50", values=authorizationMethods, textvariable=authorization)
  tkgrid(tklabel(ctrlFrame, text="Security Method:"), sticky = "w")
  tkgrid(ctrlFrame$env$comboAuth, padx = 10, pady = 5)
  
  tkgrid(tklabel(ctrlFrame, text="User Name:"), sticky = "w")
  tkgrid(entry.Name, padx = 10, pady = 5)
  tkgrid(tklabel(ctrlFrame, text="Password:"), sticky = "w")  
  tkgrid(entry.Password, padx = 10, pady = 5)
  
  #Create dropdown list menu items
  actions <- c("Create AF OSIRDatabase Database", 
               "Create AF Category",
               "Create AF Template",
               "Create AF Element",
               "-------------------------------------",
               "Write Attribute Single Value",
               "Write Attribute Set Of Values",
               "Update Attribute Value",
               "Get Attribute Snapshot Value",
               "Get Attribute Stream Values",
               "Payload with selected fields",
               "Batch Writes and reads",
               "-------------------------------------",
               "Delete AF Element",
               "Delete AF Template",
               "Delete AF Category",
               "Delete AF OSIRDatabase Database")
  dlg$env$combo <- ttkcombobox(ctrlFrame, width="50", values=actions, textvariable=Selection)
  tkgrid(tklabel(ctrlFrame, text="Action:"), sticky = "w")
  tkgrid(dlg$env$combo, padx = 10, pady = 5)
  
  #Run button click event handler
  OnRun <- function() {
    authType <- tclvalue(authorization)
    if(authType == "Kerberos"){
      authType <- "gssnegotiate"
    } else {
      authType <- "basic"
    }
    
    switch(tclvalue(Selection),
           "Create AF OSIRDatabase Database" = createDatabase(tclvalue(PIWebAPIUrl), tclvalue(AssetServer), tclvalue(Name), tclvalue(Password), authType),
           "Create AF Category" = createCategory(tclvalue(PIWebAPIUrl), tclvalue(AssetServer), tclvalue(Name), tclvalue(Password), authType),
           "Create AF Template" = createTemplate(tclvalue(PIWebAPIUrl), tclvalue(AssetServer), tclvalue(PIServer), tclvalue(Name), tclvalue(Password), authType),
           "Create AF Element" = createElement(tclvalue(PIWebAPIUrl), tclvalue(AssetServer), tclvalue(Name), tclvalue(Password), authType),
           "Create Element Attribute" = createAttribute(tclvalue(PIWebAPIUrl), tclvalue(AssetServer), tclvalue(Name), tclvalue(Password), authType),
           
           "Write Attribute Single Value" = writeSingleValue(tclvalue(PIWebAPIUrl), tclvalue(AssetServer), tclvalue(Name), tclvalue(Password), authType),
           "Write Attribute Set Of Values" = writeDataSet(tclvalue(PIWebAPIUrl), tclvalue(AssetServer), tclvalue(Name), tclvalue(Password), authType),
           "Update Attribute Value" = updateAttributeValue(tclvalue(PIWebAPIUrl), tclvalue(AssetServer), tclvalue(Name), tclvalue(Password), authType),
           "Get Attribute Snapshot Value" = readAttributeSnapshot(tclvalue(PIWebAPIUrl), tclvalue(AssetServer), tclvalue(Name), tclvalue(Password), authType),
           "Get Attribute Stream Values" = readAttributeStream(tclvalue(PIWebAPIUrl), tclvalue(AssetServer), tclvalue(Name), tclvalue(Password), authType),
           "Payload with selected fields" = readAttributeSelectedFields(tclvalue(PIWebAPIUrl), tclvalue(AssetServer), tclvalue(Name), tclvalue(Password), authType),
           "Batch Writes and reads" = doBatchCall(tclvalue(PIWebAPIUrl), tclvalue(AssetServer), tclvalue(Name), tclvalue(Password), authType),
           
           "Delete Element Attribute" = deleteAttribute(tclvalue(PIWebAPIUrl), tclvalue(AssetServer), tclvalue(Name), tclvalue(Password), authType),
           "Delete AF Element" = deleteElement(tclvalue(PIWebAPIUrl), tclvalue(AssetServer), tclvalue(Name), tclvalue(Password), authType),
           "Delete AF Template" = deleteTemplate(tclvalue(PIWebAPIUrl), tclvalue(AssetServer), tclvalue(Name), tclvalue(Password), authType),
           "Delete AF Category" = deleteCategory(tclvalue(PIWebAPIUrl), tclvalue(AssetServer), tclvalue(Name), tclvalue(Password), authType),
           "Delete AF OSIRDatabase Database" = deleteDatabase(tclvalue(PIWebAPIUrl), tclvalue(AssetServer), tclvalue(Name), tclvalue(Password), authType)
    )
  }
  
  #Close button click event handler
  OnClose <- function()
  { 
    tkdestroy(dlg) 
  }
  
  Run.but <-tkbutton(ctrlFrame, width="10", text="Execute Call", command=OnRun)
  Close.but <-tkbutton(ctrlFrame, width="10", text="Close", command=OnClose)
  tkgrid(Run.but, Close.but, padx = 5, pady = c(5, 5), sticky = "w")
  
  return(dlg)
}

#Boot sample code
set_config( config( ssl_verifypeer = 0L ) )
if((Sys.getenv("TESTING") != TRUE)){
  runPIWebAPISamples()
}

#Create sample data used by subsequent calls
createTestData <- function(){
  dataTimeStamp <- seq(as.POSIXct(Sys.Date() - 1), as.POSIXct(Sys.Date() - 2), by = "-5 min")[1:100]
  dataValue <- round(runif(100, 1, 1000), 4)
  ds <- data.frame(Timestamp=dataTimeStamp, Value=dataValue)
  return(ds)
}

#Create CORS header required for POST, PUT, PATCH or DELETE
callHeaders <- function(){
  header <- c("XMLHttpRequest")
  names(header) <- "X-Requested-With"  
  return(header)
}

#Output error to the console
# @param {*} response string: Json error object
#
errorHandler <- function(response){
  jsonRespParsed<-content(response,as="parsed")
  print(jsonRespParsed)
}

#PI Web API Calls ------------------------------------------------------------------------------------------------------------------------------------------------------------------------

#Create OSIRDatabase database
# @param {*} PIWebAPIUrl string: Location of the PI Web API instance
# @param {*} AssetServer  string:  Name of the PI Web API Asset Server (AF)
# @param {*} Name string: The user's credentials name
# @param {*} Password string: The user's credentials password
# @param {*} AuthType string: Authorization type:  basic or kerberos
#
createDatabase <- function(PIWebAPIUrl, AssetServer, Name, Password, AuthType){
  #Clear the console   
  print(cat("\014"))
  
  print("createDatabase")
  
  #Get AF server WebId
  urlFindAFAssetServer <- paste(PIWebAPIUrl, "/assetservers?path=\\\\", AssetServer, sep = "")
  print("Get asset server:")
  print(urlFindAFAssetServer)
  response <- GET(urlFindAFAssetServer, authenticate(Name, Password, type=AuthType))
  jsonRespParsed<-content(response,as="parsed")
  if(status_code(response) < 200 | status_code(response) > 300){
    print(jsonRespParsed)
    return(status_code(response))
  } else {
    print("AF server found")
  }
  print("-------------------------------------------------------------------------------------------------------------------------------")

  #Create url and execute the call
  lstCreateDatabase = list(Name=databaseName, Description="Sample Web.api database", ExtendedProperties={})
  urlCreateAFSampleDatabase <- paste(jsonRespParsed$Links$Self, "/assetdatabases",  sep = "")
  print("Create database:")
  print(urlCreateAFSampleDatabase)
  print("Body:")
  print(unlist(lstCreateDatabase))
  response <- POST(urlCreateAFSampleDatabase, authenticate(Name, Password, type=AuthType), body=lstCreateDatabase, encode = "json", add_headers(.headers = callHeaders()))
  
  #Format and output the result
  if(status_code(response) == 201) {
    print("Database OSIRDatabase created")
  } else {
    #Error occurred
    errorHandler(response)
  }
  print(paste("Returned status", status_code(response), sep=" "))
  print("-------------------------------------------------------------------------------------------------------------------------------")
  
  return(status_code(response))
}

#Create an AF category
# @param {*} PIWebAPIUrl string: Location of the PI Web API instance
# @param {*} AssetServer  string:  Name of the PI Web API Asset Server (AF)
# @param {*} Name string: The user's credentials name
# @param {*} Password string: The user's credentials password
# @param {*} AuthType string: Authorization type:  basic or kerberos
#
createCategory <- function (PIWebAPIUrl, AssetServer, Name, Password, AuthType){
  #Clear the console
  print(cat("\014"))
  
  print("createCategory")
  
  #Get OSIRDatabase database WebId
  urlFindSampleDatabase <- paste(PIWebAPIUrl, "/assetdatabases?path=\\\\", AssetServer, "\\", databaseName, sep = "")
  print("Get database:")
  print(urlFindSampleDatabase)
  response <- GET(urlFindSampleDatabase, authenticate(Name, Password, type=AuthType))
  jsonRespParsed<-content(response,as="parsed") 
  if(status_code(response) < 200 | status_code(response) > 300){
    print(jsonRespParsed)
    return(status_code(response))
  }
  print("-------------------------------------------------------------------------------------------------------------------------------")
  
  #Create url and execute the call
  lstCategory = list(Name=categoryName, Description="Sample machine category")
  urlCreateCategory <- paste(jsonRespParsed$Links$Self, "/elementcategories",  sep = "")
  print("Create category:")
  print(urlCreateCategory)
  print("Body:")
  print(unlist(lstCategory))

  response <- POST(urlCreateCategory, authenticate(Name, Password, type=AuthType), body = lstCategory, encode = "json", add_headers(.headers = callHeaders()))
  print(paste("Returned status", status_code(response), sep=" "))
  #Format and output the result
  if(status_code(response) == 201) {
    print("Category OSIRCategory created")
  } else {
    #Error occurred
    errorHandler(response)
  } 
  print(paste("Returned status", status_code(response), sep=" "))
  print("-------------------------------------------------------------------------------------------------------------------------------")
  
  return(status_code(response))
}

#Create an AF template
# @param {*} PIWebAPIUrl string: Location of the PI Web API instance
# @param {*} AssetServer  string:  Name of the PI Web API Asset Server (AF)
# @param {*} PIServer  string:  Name of the PI Server
# @param {*} Name string: The user's credentials name
# @param {*} Password string: The user's credentials password
# @param {*} AuthType string: Authorization type:  basic or kerberos
#
createTemplate <- function (PIWebAPIUrl, AssetServer, PIServer, Name, Password, AuthType){
  statusCode = 0
  #Clear the console   
  print(cat("\014"))
  
  print("createTemplate")
  
  #Get OSIRDatabase database WebId
  urlFindSampleDatabase <- paste(PIWebAPIUrl, "/assetdatabases?path=\\\\", AssetServer, "\\", databaseName, sep = "")
  print("Get database:")
  print(urlFindSampleDatabase)
  print("-------------------------------------------------------------------------------------------------------------------------------")
  
  response <- GET(urlFindSampleDatabase, authenticate(Name, Password, type=AuthType))
  jsonRespParsed<-content(response,as="parsed")
  if(status_code(response) < 200 | status_code(response) > 300){
    print(jsonRespParsed)
    return(status_code(response))
  }

  #Create url and execute the call
  urlCreateElementTemplate <- paste(jsonRespParsed$Links$Self, "/elementtemplates",  sep = "")
  lstTemplate = list(Name=templateName, Description="Sample Machine Template", CategoryNames=I(c(categoryName)))
  print("Create template:")
  print(urlCreateElementTemplate)
  print("Body:")
  print(unlist(lstTemplate))
  
  #CategoryNames: I(c()) required to properly pass the value
  response <- POST(urlCreateElementTemplate, authenticate(Name, Password, type=AuthType), body=list(Name=templateName, Description="Sample Machine Template", CategoryNames=I(c(categoryName)), AllowElementToExtend="true"), encode = "json", add_headers(.headers = callHeaders()))
  
  #If template was created add attributes
  if(status_code(response) == 201) {
    print(paste("Returned status", status_code(response), sep=" "))
    print("Template OSIRTemplate created")
    print("-------------------------------------------------------------------------------------------------------------------------------")
    
    #Get the created templates WebId
    urlFindMachineTemplate <- paste(PIWebAPIUrl, "/elementtemplates?path=\\\\", AssetServer, "\\", databaseName, "\\ElementTemplates[", templateName, "]", sep = "")
    print("Find created template")
    print(urlFindMachineTemplate)
    
    response <- GET(urlFindMachineTemplate, authenticate(Name, Password, type=AuthType), encode = "json")
    jsonRespParsed<-content(response,as="parsed")
    if(status_code(response) == 200) {
      print("Template found")
    }
    else {
      print(paste("Error Finding created template:", jsonRespParsed, sep=" "))
    }
    print("-------------------------------------------------------------------------------------------------------------------------------")
    
    #Add template attributes
    urlAddTemplateAttributes <- paste(jsonRespParsed$Links$Self, "/attributetemplates",  sep = "")
    lstActive = list(Name=attributeActiveName, Description="", IsConfigurationItem="true", Type="Boolean")
    print("Create OSIRAttributeActive attribute:")
    print(urlAddTemplateAttributes)
    print("Body:")
    print(unlist(lstActive))
    
    response <- POST(urlAddTemplateAttributes, authenticate(Name, Password, type=AuthType), body = lstActive, encode = "json", add_headers(.headers = callHeaders()))
    statusCode = status_code(response)
    if(statusCode == 201) {
      print("OSIRAttributeActive attribute created")
    }
    else {
      jsonRespParsed<-content(response,as="parsed")
      print(paste("Error creating OSIRAttributeActive attribute:", jsonRespParsed, sep=" "))
    }
    print("-------------------------------------------------------------------------------------------------------------------------------")
    
    #Add Sinusoid
    configString <- paste("\\\\", PIServer, "\\Sinusoid",  sep = "")
    lstSinusoid = list(Name=attributeSinusoidName, Description="", IsConfigurationItem="false", Type="Double",  DataReferencePlugIn="PI Point", ConfigString= configString)
    print("Create OSIRAttributeSinusoid tag attribute:")
    print("Body:")
    print(unlist(lstSinusoid))
    response <- POST(urlAddTemplateAttributes, authenticate(Name, Password, type=AuthType), body = lstSinusoid, encode = "json", add_headers(.headers = callHeaders()))
    statusCode = status_code(response)
    if(status_code(response) == 201) {
      print("OSIRAttributeSinusoid attribute created")
    }
    else {
      jsonRespParsed<-content(response,as="parsed")
      print(paste("Error creating OSIRAttributeActive attribute:", jsonRespParsed, sep=" "))
    }
    print("-------------------------------------------------------------------------------------------------------------------------------")
    
    
    #Add the OSIRAttributeSampleTag attribute
    configStringSampleTag <- paste("\\\\", PIServer, "\\%Element%_", tagName, ";ReadOnly=False;ptclassname=classic;pointtype=Float64;pointsource=webapi",  sep = "")
    lstSampleTag = list(Name=attributeSampleTagName, Description="Sample tag", IsConfigurationItem="false", Type="Double",  DataReferencePlugIn="PI Point", ConfigString= configStringSampleTag)
    print("Create OSIRAttributeSampleTag tag attribute:")
    print("Body:")
    print(unlist(lstSampleTag)) 
    
    response <- POST(urlAddTemplateAttributes, authenticate(Name, Password, type=AuthType), body = lstSampleTag, encode = "json", add_headers(.headers = callHeaders()))
    statusCode = status_code(response)
    if(status_code(response) == 201) {
      print("OSIRAttributeSampleTag attribute created")
    }
    else {
      jsonRespParsed<-content(response,as="parsed")
      print(paste("Error creating OSIRAttributeSampleTag attribute:", jsonRespParsed, sep=" "))
      if(jsonRespParsed$Errors[[1]] == "'OSIRAttributeSampleTag' already exists."){
        statusCode = 201
      }
    }
    print("-------------------------------------------------------------------------------------------------------------------------------")
    
  } else {
    #Error occurred creating template
    statusCode = status_code(response)
    errorHandler(response)
    print(paste("Returned status", status_code(response), sep=" "))
  }
  
  return(statusCode)
}

#Create an AF element
# @param {*} PIWebAPIUrl string: Location of the PI Web API instance
# @param {*} AssetServer  string:  Name of the PI Web API Asset Server (AF)
# @param {*} Name string: The user's credentials name
# @param {*} Password string: The user's credentials password
# @param {*} AuthType string: Authorization type:  basic or kerberos
#
createElement <- function (PIWebAPIUrl, AssetServer, Name, Password, AuthType){
  #Clear the console   
  print(cat("\014"))
  
  print("createElement")
  
  #Get the OSIRDatabase database WebId
  urlFindSampleDatabase <- paste(PIWebAPIUrl, "/assetdatabases?path=\\\\", AssetServer, "\\", databaseName, sep = "")
  print("Get database:")
  print(urlFindSampleDatabase)
  print("-------------------------------------------------------------------------------------------------------------------------------")
  
  response <- GET(urlFindSampleDatabase, authenticate(Name, Password, type=AuthType))
  jsonRespParsed<-content(response,as="parsed") 
  if(status_code(response) < 200 | status_code(response) > 300){
    print(jsonRespParsed)
    return(status_code(response))
  }

  #Create url and execute the call
  lstElement = list(Name=elementName, Description="Sample equipment element", TemplateName=templateName, ExtendedProperties={})
  urlCreateElement <- paste(jsonRespParsed$Links$Self, "/elements",  sep = "")
  response <- POST(urlCreateElement, authenticate(Name, Password, type=AuthType), body= lstElement, encode = "json", add_headers(.headers = callHeaders()))
  print("Create element:")
  print(urlCreateElement)
  print("Body:")
  print(unlist(lstElement))
  
  #If element was created then create attribute tags
  if(status_code(response) == 201) {
    print("Equipment OSIRElement created")
    print("-------------------------------------------------------------------------------------------------------------------------------")
    
    #Get the element WebId
    urlFindCreatedElement <- paste(PIWebAPIUrl, "/elements?path=\\\\", AssetServer, "\\", databaseName, "\\", elementName, sep = "")
    response <- GET(urlFindCreatedElement, authenticate(Name, Password, type=AuthType), encode = "json")
    jsonRespParsed<-content(response,as="parsed")
    print("Find created element")
    print(urlFindCreatedElement)
    if(status_code(response) == 200) {
      print("Element found")
    }
    else {
      print(paste("Error Finding created element:", jsonRespParsed, sep=" "))
    }
    print("-------------------------------------------------------------------------------------------------------------------------------")   
    
    
    #Create the tags based on the template configuration
    lstChildElements = list(includeChildElements="true")
    urlCreateElementAttributeReferences <- paste(PIWebAPIUrl, "/elements/", jsonRespParsed$WebId, "/config", sep = "")
    response <- POST(urlCreateElementAttributeReferences, authenticate(Name, Password, type=AuthType), body=lstChildElements, encode = "json", add_headers(.headers = callHeaders()))
    jsonRespParsed<-content(response,as="parsed")
    print("Create element tag references")
    print(urlCreateElementAttributeReferences)
    print("Body:")
    print(unlist(lstChildElements))
    if(status_code(response) == 200) {
      print("Created the tag references based on the template configuration")
    }
    else {
      print(paste("Error creating the tag references based on the template configuration:", jsonRespParsed, sep=" "))
    }    
    print("-------------------------------------------------------------------------------------------------------------------------------")
  } else {
    #Error occurred
    errorHandler(response)
  }
  print(paste("Returned status", status_code(response), sep=" "))
  return(status_code(response))
}

#Write a single value to the OSIRAttributeSampleTag
# @param {*} PIWebAPIUrl string: Location of the PI Web API instance
# @param {*} AssetServer  string:  Name of the PI Web API Asset Server (AF)
# @param {*} Name string: The user's credentials name
# @param {*} Password string: The user's credentials password
# @param {*} AuthType string: Authorization type:  basic or kerberos
#
writeSingleValue <- function(PIWebAPIUrl, AssetServer, Name, Password, AuthType){
  #Clear the console   
  print(cat("\014"))
  
  print("writeSingleValue")
  
  #Generate value to write
  attributeValue <- runif(1, 1, 1000)
  
  #Get attribute OSIRAttributeSampleTag WebId
  urlFindElementAttributeSampleTag <- paste(PIWebAPIUrl, "/attributes?path=\\\\", AssetServer, "\\", databaseName, "\\", elementName, "|", attributeSampleTagName, sep = "")
  response <- GET(urlFindElementAttributeSampleTag, authenticate(Name, Password, type=AuthType), encode = "json")
  print("Find tag:")
  print(urlFindElementAttributeSampleTag)
  jsonRespParsed<-content(response,as="parsed")
  if(status_code(response) < 200 | status_code(response) > 300){
    print(jsonRespParsed)
    return(status_code(response))
  }
  print("-------------------------------------------------------------------------------------------------------------------------------")

  #Create url and execute the call
  lstUpdate = list(Value=attributeValue)
  urlUpdateSampleTagValue <- paste(jsonRespParsed$Links$Self, "/value", sep = "")
  response <- PUT(urlUpdateSampleTagValue, authenticate(Name, Password, type=AuthType), body=lstUpdate, encode = "json", add_headers(.headers = callHeaders()))
  print("Write tag value:")
  print(urlUpdateSampleTagValue) 
  print("Body:")
  print(unlist(lstUpdate))
  print("-------------------------------------------------------------------------------------------------------------------------------")
  
  #Format and output the result
  jsonRespParsed<-content(response,as="parsed")
  if(status_code(response) == 204) {
    print(paste("Attribute OSIRAttributeSampleTag written value:", attributeValue, sep = " "))
  } else {
    #Error ocurred
    errorHandler(response)
  }
  print(paste("Returned status", status_code(response), sep = " "))
  print("-------------------------------------------------------------------------------------------------------------------------------")

  return(status_code(response))
}

#Write a set of recorded values to the OSIRAttributeSampleTag
# @param {*} PIWebAPIUrl string: Location of the PI Web API instance
# @param {*} AssetServer  string:  Name of the PI Web API Asset Server (AF)
# @param {*} Name string: The user's credentials name
# @param {*} Password string: The user's credentials password
# @param {*} AuthType string: Authorization type:  basic or kerberos
#
writeDataSet <- function(PIWebAPIUrl, AssetServer, Name, Password, AuthType){
  #Clear the console   
  print(cat("\014"))
  
  print("writeDataSet")
  
  #Get values to write
  dataSet <- createTestData()
  
  #Get attribute OSIRAttributeSampleTag WebId
  urlFindElementAttributeSampleTag <- paste(PIWebAPIUrl, "/attributes?path=\\\\", AssetServer, "\\", databaseName, "\\", elementName, "|", attributeSampleTagName, sep = "")
  response <- GET(urlFindElementAttributeSampleTag, authenticate(Name, Password, type=AuthType), encode = "json")
  print("Find tag:")
  print(urlFindElementAttributeSampleTag)
  jsonRespParsed<-content(response,as="parsed")
  if(status_code(response) < 200 | status_code(response) > 300){
    print(jsonRespParsed)
    return(status_code(response))
  }
  print("-------------------------------------------------------------------------------------------------------------------------------")

  #Create url and execute the call
  urlWriteSampleTagValues <- paste(PIWebAPIUrl, "/streams/", jsonRespParsed$WebId, '/recorded', sep = "")
  response <- POST(urlWriteSampleTagValues, authenticate(Name, Password, type=AuthType), body= dataSet, encode = "json", add_headers(.headers = callHeaders()))
  print("Stream 100 values:")
  print(urlWriteSampleTagValues)
  print("Body:")
  print(dataSet)
  jsonRespParsed<-content(response,as="parsed")
  if(status_code(response) < 200 | status_code(response) > 300){
    print(jsonRespParsed)
    return(status_code(response))
  }
  print("-------------------------------------------------------------------------------------------------------------------------------")
  
  #Format and output the result
  if(status_code(response) == 202) {
    print("Attribute OSIRAttributeSampleTag streamed 100 values")
  } else {
    #Error occurred
    errorHandler(response)
  }
  print(paste("Returned status", status_code(response), sep=" "))
  print("-------------------------------------------------------------------------------------------------------------------------------")
  return(status_code(response))
}

#Update an element attribute value
# @param {*} PIWebAPIUrl string: Location of the PI Web API instance
# @param {*} AssetServer  string:  Name of the PI Web API Asset Server (AF)
# @param {*} Name string: The user's credentials name
# @param {*} Password string: The user's credentials password
# @param {*} AuthType string: Authorization type:  basic or kerberos
#
updateAttributeValue <- function (PIWebAPIUrl, AssetServer, Name, Password, AuthType){
  #Clear the console   
  print(cat("\014"))
  
  print("updateAttributeValue")
  
  #Get the WebId of the attribute to update
  urlFindElementAttribute <- paste(PIWebAPIUrl, "/attributes?path=\\\\", AssetServer, "\\", databaseName, "\\", elementName, "|", attributeActiveName, sep = "")
  response <- GET(urlFindElementAttribute, authenticate(Name, Password, type=AuthType), encode = "json")
  print("Find attribute:")
  print(urlFindElementAttribute)
  jsonRespParsed<-content(response,as="parsed")
  if(status_code(response) < 200 | status_code(response) > 300){
    print(jsonRespParsed)
    return(status_code(response))
  }
  print("-------------------------------------------------------------------------------------------------------------------------------")

  #Create url and execute the call
  lstValue = list(Value="true")
  urlUpdateElementAttributeValue <- paste(jsonRespParsed$Links$Self, "/value", sep = "")
  response <- PUT(urlUpdateElementAttributeValue, authenticate(Name, Password, type=AuthType), body=lstValue, encode = "json", add_headers(.headers = callHeaders()))
  jsonRespParsed<-content(response,as="parsed")
  print("Update attribute value:")
  print(urlUpdateElementAttributeValue)
  print("Body:")
  print(unlist(lstValue))
  print("-------------------------------------------------------------------------------------------------------------------------------")
  
  #Format and output the result
  if(status_code(response) == 204) {
    print("Attribute OSIRAttributeActive value set to true")
  } else {
    #Error occurred
    errorHandler(response)
  }
  print(paste("Returned status", status_code(response), sep=" "))
  print("-------------------------------------------------------------------------------------------------------------------------------")
  
  return(status_code(response))
}

#Read OSIRAttributeSampleTag snapshot value
# @param {*} PIWebAPIUrl string: Location of the PI Web API instance
# @param {*} AssetServer  string:  Name of the PI Web API Asset Server (AF)
# @param {*} Name string: The user's credentials name
# @param {*} Password string: The user's credentials password
# @param {*} AuthType string: Authorization type:  basic or kerberos
#
readAttributeSnapshot <- function(PIWebAPIUrl, AssetServer, Name, Password, AuthType){
  #Clear the console   
  print(cat("\014"))
  
  print("readAttributeSnapshot")
  
  #Find attribute OSIRAttributeSampleTag
  urlFindElementAttributeSampleTag <- paste(PIWebAPIUrl, "/attributes?path=\\\\", AssetServer, "\\", databaseName, "\\", elementName, "|", attributeSampleTagName, sep = "")
  response <- GET(urlFindElementAttributeSampleTag, authenticate(Name, Password, type=AuthType), encode = "json")
  print("Find tag:")
  print(urlFindElementAttributeSampleTag)
  jsonRespParsed<-content(response,as="parsed")
  if(status_code(response) < 200 | status_code(response) > 300){
    print(jsonRespParsed)
    return(status_code(response))
  }
  print("-------------------------------------------------------------------------------------------------------------------------------")
  
  #Create url and execute the call
  urlGetSampleTagValue <- paste(PIWebAPIUrl, "/streams/", jsonRespParsed$WebId, '/value', sep = "")
  response <- GET(urlGetSampleTagValue, authenticate(Name, Password, type=AuthType), encode = "json")
  print("Get snapshot value:")
  print(urlGetSampleTagValue)
  print("-------------------------------------------------------------------------------------------------------------------------------")
  
  #Format and output the result
  jsonRespParsed<-content(response,as="parsed")
  if(status_code(response) >= 200 & status_code(response) < 300) {
    print("OSIRAttributeSampleTag Snapshot Value")
    df <- data.frame(jsonRespParsed)
    df$Timestamp <- strptime(df$Timestamp, format='%Y-%m-%dT%H:%M:%OS')    
    print(df)  
  } else {
    #Error occurred
    errorHandler(response)
  } 
  print(paste("Returned status", status_code(response), sep=" "))
  print("-------------------------------------------------------------------------------------------------------------------------------")
  
  return(status_code(response))
}

#Read OSIRAttributeSampleTag values from a stream
# @param {*} PIWebAPIUrl string: Location of the PI Web API instance
# @param {*} AssetServer  string:  Name of the PI Web API Asset Server (AF)
# @param {*} Name string: The user's credentials name
# @param {*} Password string: The user's credentials password
# @param {*} AuthType string: Authorization type:  basic or kerberos
#
readAttributeStream <- function(PIWebAPIUrl, AssetServer, Name, Password, AuthType) {
  #Clear the console   
  print(cat("\014"))
  
  print("readAttributeTagData")
  
  #Get attribute OSIRAttributeSampleTag WebId
  urlFindElementAttributeSampleTag <- paste(PIWebAPIUrl, "/attributes?path=\\\\", AssetServer, "\\", databaseName, "\\", elementName, "|", attributeSampleTagName, sep = "")
  response <- GET(urlFindElementAttributeSampleTag, authenticate(Name, Password, type=AuthType), encode = "json")
  print("Find tag:")
  print(urlFindElementAttributeSampleTag)
  jsonRespParsed<-content(response,as="parsed")
  if(status_code(response) < 200 | status_code(response) > 300){
    print(jsonRespParsed)
    return(status_code(response))
  }
  print("-------------------------------------------------------------------------------------------------------------------------------")
  
  #Create url and execute the call
  urlGetSampleTagValues <- paste(PIWebAPIUrl, "/streams/", jsonRespParsed$WebId, '/recorded?startTime=*-2d', sep = "")
  response <- GET(urlGetSampleTagValues, authenticate(Name, Password, type=AuthType), encode = "json")
  print("Get values:")
  print(urlGetSampleTagValues)
  print("-------------------------------------------------------------------------------------------------------------------------------")
  
  #Format and output the result
  jsonRespParsed<-content(response,as="parsed")
  if(status_code(response) >= 200 & status_code(response) < 300) {
    print("OSIRAttributeSampleTag Values")
    #Convert result into a data frame
    df <- as.data.frame(do.call(rbind, jsonRespParsed$Items))
    df[['Timestamp']] <- strptime(df[['Timestamp']], format='%Y-%m-%dT%H:%M:%OS')    
    print(df)
  } else {
    #Error occurred
    errorHandler(response)
  }
  print(paste("Returned status", status_code(response), sep=" "))
  print("-------------------------------------------------------------------------------------------------------------------------------")
  
  return(status_code(response))
}

#Read OSIRAttributeSampleTag values with selected fields to reduce payload size
# @param {*} PIWebAPIUrl string: Location of the PI Web API instance
# @param {*} AssetServer  string:  Name of the PI Web API Asset Server (AF)
# @param {*} Name string: The user's credentials name
# @param {*} Password string: The user's credentials password
# @param {*} AuthType string: Authorization type:  basic or kerberos
#
readAttributeSelectedFields <- function(PIWebAPIUrl, AssetServer, Name, Password, AuthType){
  #Clear the console   
  print(cat("\014"))
  
  print("readAttributeSelectedFields")
  
  #Get attribute OSIRAttributeSampleTag WebId
  urlFindElementAttributeSampleTag <- paste(PIWebAPIUrl, "/attributes?path=\\\\", AssetServer, "\\", databaseName, "\\", elementName, "|", attributeSampleTagName, sep = "")
  response <- GET(urlFindElementAttributeSampleTag, authenticate(Name, Password, type=AuthType), encode = "json")
  print("Find tag:")
  print(urlFindElementAttributeSampleTag)
  jsonRespParsed<-content(response,as="parsed")
  if(status_code(response) < 200 | status_code(response) > 300){
    print(jsonRespParsed)
    return(status_code(response))
  }
  print("-------------------------------------------------------------------------------------------------------------------------------")
  
  
  #Create url and execute the call
  urlGetSampleTagValues <- paste(PIWebAPIUrl, "/streams/", jsonRespParsed$WebId, '/recorded?startTime=*-2d&selectedFields=Items.Timestamp;Items.Value', sep = "")
  response <- GET(urlGetSampleTagValues, authenticate(Name, Password, type=AuthType), encode = "json")
  print("Get tag values:")
  print(urlGetSampleTagValues)
  print("-------------------------------------------------------------------------------------------------------------------------------")
  
  #Format and output the result
  jsonRespParsed<-content(response,as="parsed")
  if(status_code(response) >= 200 & status_code(response) < 300) {
    print("OSIRAttributeSampleTag Values")
    df <- as.data.frame(do.call(rbind, jsonRespParsed$Items))
    #df[['Timestamp']] <- strptime(df[['Timestamp']], format='%Y-%m-%dT%H:%M:%OS')    
    print(df)
  } else {
    #Error occurred
    errorHandler(response)
  } 
  print(paste("Returned status", status_code(response), sep=" "))
  print("-------------------------------------------------------------------------------------------------------------------------------")
  
  return(status_code(response))
}

#Create and execute a PI Web API batch call
# @param {*} PIWebAPIUrl string: Location of the PI Web API instance
# @param {*} AssetServer  string:  Name of the PI Web API Asset Server (AF)
# @param {*} Name string: The user's credentials name
# @param {*} Password string: The user's credentials password
# @param {*} AuthType string: Authorization type:  basic or kerberos
#
doBatchCall <- function(PIWebAPIUrl, AssetServer, Name, Password, AuthType){
  #Clear the console   
  print(cat("\014"))
  
  print("doBatchCall")
  
  #Get attribute OSIRAttributeSampleTag WebId
  urlFindElementAttributeSampleTag <- paste(PIWebAPIUrl, "/attributes?path=\\\\", AssetServer, "\\", databaseName, "\\", elementName, "|", attributeSampleTagName, sep = "")
  response <- GET(urlFindElementAttributeSampleTag, authenticate(Name, Password, type=AuthType), encode = "json")
  print("Find tag:")
  print(urlFindElementAttributeSampleTag)
  jsonRespParsed<-content(response,as="parsed")
  if(status_code(response) < 200 | status_code(response) > 300){
    print(jsonRespParsed)
    return(status_code(response))
  }
  print("-------------------------------------------------------------------------------------------------------------------------------")
  
  
  #Create batch call body
  calls <- NULL
  calls$"1" <- NULL
  calls$"1"$Method <- "GET"
  calls$"1"$Resource <- paste(PIWebAPIUrl, "/attributes?path=\\\\", AssetServer, "\\", databaseName, "\\", elementName, "|", attributeSampleTagName, sep = "")
  calls$"1"$Content <- "{}"
  
  calls$"2" <- NULL
  calls$"2"$Method <- "GET"
  calls$"2"$Resource <- paste(PIWebAPIUrl, "/streams/{0}/value", sep="")
  calls$"2"$Content <- "{}"
  calls$"2"$Parameters <- I(c("$.1.Content.WebId"))
  calls$"2"$ParentIds <- I(c("1"))
  
  calls$"3" <- NULL
  calls$"3"$Method <- "GET"
  calls$"3"$Resource <- paste(PIWebAPIUrl, "/streams/{0}/recorded?maxCount=10", sep="")
  calls$"3"$Content <- "{}"
  calls$"3"$Parameters <- I(c("$.1.Content.WebId"))
  calls$"3"$ParentIds <- I(c("1"))
  
  calls$"4" <- NULL
  calls$"4"$Method <- "PUT"
  calls$"4"$Resource <- paste(PIWebAPIUrl, "/attributes/{0}/value", sep="")
  calls$"4"$Content <- "{\"Value\":\"123\"}"  
  calls$"4"$Parameters <- I(c("$.1.Content.WebId"))
  calls$"4"$ParentIds <- I(c("1"))
  
  calls$"5" <- NULL
  calls$"5"$Method <- "POST"
  calls$"5"$Resource <-  paste(PIWebAPIUrl, "/streams/{0}/recorded", sep="")
  calls$"5"$Content <- "[{\"Value\":\"111\"},{\"Value\":\"222\"},{\"Value\":\"333\"}]"    
  calls$"5"$Parameters <- I(c("$.1.Content.WebId"))
  calls$"5"$ParentIds <- I(c("1"))
  
  calls$"6" <- NULL
  calls$"6"$Method <- "GET"
  calls$"6"$Resource <-  paste(PIWebAPIUrl, "/streams/{0}/recorded?maxCount=10&selectedFields=Items.Timestamp;Items.Value", sep="")
  calls$"6"$Content <- "{}"   
  calls$"6"$Parameters <- I(c("$.1.Content.WebId"))
  calls$"6"$ParentIds <- I(c("1"))
  
  #Execute the batch
  urlExecuteBatch <- paste(PIWebAPIUrl, "/batch", sep = "")
  print("Execute batch:")
  print(urlExecuteBatch)
  print("Body:")
  print(toJSON(calls))
  print("-------------------------------------------------------------------------------------------------------------------------------")
  
  response <- POST(urlExecuteBatch, authenticate(Name, Password, type=AuthType), body = calls, encode = "json", add_headers(.headers = callHeaders()))
  
  #Format and output results
  jsonRespParsed<-content(response,as="parsed")
  
  if(status_code(response) >= 200 & status_code(response) < 300) {
    print("Results:")
    print("1: Find OSIRAttributeSampleTag")
    print(paste("Status:", jsonRespParsed$"1"$Status))
    
    print("2: Get a snapshot value")
    df <- data.frame(jsonRespParsed$"2"$Content)
    df$Timestamp <- strptime(df$Timestamp, format='%Y-%m-%dT%H:%M:%OS')    
    print(df)
    
    print("3: Get a stream of recorded values")
    df <- as.data.frame(do.call(rbind, jsonRespParsed$"3"$Content$Items))
    df$Timestamp <- strptime(df$Timestamp, format='%Y-%m-%dT%H:%M:%OS')    
    print(df)
    
    print("4: Write a single snapshot value")
    print(paste("Status:", jsonRespParsed$"4"$Status, "Content:", jsonRespParsed$"4"$Content))
    
    print("5: Write a set of recorded data")
    print(paste("Status:", jsonRespParsed$"5"$Status, "Content:", jsonRespParsed$"5"$Content))
    
    print("6: Reduced payloads with Selected Fields")
    df <- as.data.frame(do.call(rbind, jsonRespParsed$"6"$Content$Items))
    df$Timestamp <- strptime(df$Timestamp, format='%Y-%m-%dT%H:%M:%OS')    
    print(df)
  } else {
    #Error occurred
    errorHandler(response)
  }
  print(paste("Batch returned status", status_code(response), sep=" "))
  print("-------------------------------------------------------------------------------------------------------------------------------")
  
  return(status_code(response))
}

#Delete an AF element
# @param {*} PIWebAPIUrl string: Location of the PI Web API instance
# @param {*} AssetServer  string:  Name of the PI Web API Asset Server (AF)
# @param {*} Name string: The user's credentials name
# @param {*} Password string: The user's credentials password
# @param {*} AuthType string: Authorization type:  basic or kerberos
#
deleteElement <- function (PIWebAPIUrl, AssetServer, Name, Password, AuthType){
  #Clear the console   
  print(cat("\014"))
  
  print("deleteElement")
  
  #Get the WebId of the element to be deleted
  urlFindElement <- paste(PIWebAPIUrl, "/elements?path=\\\\", AssetServer, "\\", databaseName, "\\", elementName, sep = "")
  response <- GET(urlFindElement, authenticate(Name, Password, type=AuthType), encode = "json")
  print("Find element:")
  print(urlFindElement)
  jsonRespParsed<-content(response,as="parsed")
  if(status_code(response) < 200 | status_code(response) > 300){
    print(jsonRespParsed)
    return(status_code(response))
  }
  print("-------------------------------------------------------------------------------------------------------------------------------")

  #Delete the element
  response <- DELETE(jsonRespParsed$Links$Self, authenticate(Name, Password, type=AuthType), add_headers(.headers = callHeaders()))
  print("Delete element:")
  print(jsonRespParsed$Links$Self)
  
  
  #Format and output the result
  if(status_code(response) == 204) {
    print("Element OSIRElement deleted")
  } else {
    #Error occurred
    errorHandler(response)
  } 
  print(paste("Returned status", status_code(response), sep=" "))
  print("-------------------------------------------------------------------------------------------------------------------------------")
  
  return(status_code(response))
}

#Delete an AF template
# @param {*} PIWebAPIUrl string: Location of the PI Web API instance
# @param {*} AssetServer  string:  Name of the PI Web API Asset Server (AF)
# @param {*} Name string: The user's credentials name
# @param {*} Password string: The user's credentials password
# @param {*} AuthType string: Authorization type:  basic or kerberos
#
deleteTemplate <- function (PIWebAPIUrl, AssetServer, Name, Password, AuthType){
  #Clear the console   
  print(cat("\014"))
  
  print("deleteTemplate")
  
  #Get the template WebId
  urlFindElementTemplate <- paste(PIWebAPIUrl, "/elementtemplates?path=\\\\", AssetServer, "\\", databaseName, "\\ElementTemplates[", templateName, "]", sep = "")
  response <- GET(urlFindElementTemplate, authenticate(Name, Password, type=AuthType), encode = "json")
  print("Find element:")
  print(urlFindElementTemplate)
  jsonRespParsed<-content(response,as="parsed")
  if(status_code(response) < 200 | status_code(response) > 300){
    print(jsonRespParsed)
    return(status_code(response))
  }
  print("-------------------------------------------------------------------------------------------------------------------------------")

  #Delete the template
  response <- DELETE(jsonRespParsed$Links$Self, authenticate(Name, Password, type=AuthType), add_headers(.headers = callHeaders()))
  print("Delete template:")
  print(jsonRespParsed$Links$Self)
  
  #Format and output the result
  if(status_code(response) == 204) {
    print("Template OSIRTemplate deleted")
  } else {
    #Error occurred
    errorHandler(response)
  }
  print(paste("Returned status", status_code(response), sep=" "))
  print("-------------------------------------------------------------------------------------------------------------------------------")
  
  return(status_code(response))
}

#Delete an AF category
# @param {*} PIWebAPIUrl string: Location of the PI Web API instance
# @param {*} AssetServer  string:  Name of the PI Web API Asset Server (AF)
# @param {*} Name string: The user's credentials name
# @param {*} Password string: The user's credentials password
# @param {*} AuthType string: Authorization type:  basic or kerberos
#
deleteCategory <- function (PIWebAPIUrl, AssetServer, Name, Password, AuthType){
  #Clear the console   
  print(cat("\014"))
  
  print("deleteCategory")
  
  #Get category WebId
  urlFindCategory <- paste(PIWebAPIUrl, "/elementcategories?path=\\\\", AssetServer, "\\", databaseName, "\\CategoriesElement[", categoryName, "]", sep = "")
  response <- GET(urlFindCategory, authenticate(Name, Password, type=AuthType), encode = "json")
  print("Find category:")
  print(urlFindCategory)
  jsonRespParsed<-content(response,as="parsed")
  if(status_code(response) < 200 | status_code(response) > 300){
    print(jsonRespParsed)
    return(status_code(response))
  }
  print("-------------------------------------------------------------------------------------------------------------------------------")

  #Delete the category
  response <- DELETE(jsonRespParsed$Links$Self, authenticate(Name, Password, type=AuthType), add_headers(.headers = callHeaders()))
  print("Delete category:")
  print(jsonRespParsed$Links$Self)
  
  #Format and output the result
  if(status_code(response) == 204) {
    print("Category OSIRCategory deleted")
  } else {
    #Error occurred
    errorHandler(response)
  } 
  print(paste("Returned status", status_code(response), sep=" "))
  print("-------------------------------------------------------------------------------------------------------------------------------")
  
  return(status_code(response))
}

#Delete OSIRDatabase AF database
# @param {*} PIWebAPIUrl string: Location of the PI Web API instance
# @param {*} AssetServer  string:  Name of the PI Web API Asset Server (AF)
# @param {*} Name string: The user's credentials name
# @param {*} Password string: The user's credentials password
# @param {*} AuthType string: Authorization type:  basic or kerberos
#
deleteDatabase <- function(PIWebAPIUrl, AssetServer, Name, Password, AuthType){
  #Clear the console   
  print(cat("\014"))
  
  print("deleteDatabase")
  
  #Get OSIRDatabase database WebId
  urlFindSampleDatabase <- paste(PIWebAPIUrl, "/assetdatabases?path=\\\\", AssetServer, "\\", databaseName, sep = "")
  response <- GET(urlFindSampleDatabase, authenticate(Name, Password, type=AuthType))
  print("Find database:")
  print(urlFindSampleDatabase)
  jsonRespParsed<-content(response,as="parsed")
  if(status_code(response) < 200 | status_code(response) > 300){
    print(jsonRespParsed)
    return(status_code(response))
  }
  print("-------------------------------------------------------------------------------------------------------------------------------")

  #Create url and execute the call
  urlDeleteSampleDatabase <- paste(PIWebAPIUrl, "/assetdatabases/", jsonRespParsed$WebId,  sep = "")
  response <- DELETE(urlDeleteSampleDatabase, authenticate(Name, Password, type=AuthType), add_headers(.headers = callHeaders()))
  print("Delete database:")
  print(urlDeleteSampleDatabase)
  
  #Format and output the result
  if(status_code(response) == 204) {
    print("Database OSIRDatabase deleted")
  } else {
    #Error occurred
    errorHandler(response)
  }
  print(paste("Returned status", status_code(response), sep=" "))
  print("-------------------------------------------------------------------------------------------------------------------------------")
  
  return(status_code(response))
}
