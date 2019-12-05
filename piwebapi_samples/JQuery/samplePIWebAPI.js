  var databaseName = 'OSIjQueryDatabase'
  var categoryName = 'OSIjQueryCategory'
  var templateName = 'OSIjQueryTemplate'
  var attributeActiveName = 'OSIjQueryAttributeActive'
  var attributeSinusoidName = 'OSIjQueryAttributeSinusoid'
  var tagName = 'OSIjQuerySampleTag'
  var attributeSampleTagName = 'OSIjQueryAttributeSampleTag'
  var elementName = 'OSIjQueryElement'

  /**
   * Returns true if AuthType equals kerberos case insensitive
   * @param {*} AuthType string: Authorization type:  basic or kerberos
  */
  function authTypeKerberos (AuthType) {
    return AuthType.toUpperCase() === 'KERBEROS'
  }

  /**
   * Create API call headers based on authorization type
   * @param {*} Name string: The user's credentials name
   * @param {*} Password string: The user's credentials password
   * @param {*} AuthType string: Authorization type:  basic or kerberos
   */
  function callHeaders (Name, Password, AuthType) {
    var callHeaders
    if ((authTypeKerberos(AuthType))) {
      //  build a kerberos authentication header
      callHeaders = {
        'X-Requested-With': 'XMLHttpRequest'
      }
    }
    else {
      //  build a basic authentication header
      callHeaders = {
        'Authorization': AuthType + ' ' + btoa(Name + ':' + Password),
        'X-Requested-With': 'XMLHttpRequest'
      }
    }
    return callHeaders
  }

  /**
   * Create sample data set
   */
  function createTestData () {
    var dteTestData = []
    var fiveMinutes = 5 * 60 * 1000
    var dte = new Date(new Date().setHours(0, 0, 0, 0))
    dte.setDate(dte.getDate() - 2)
    for (var i = 1; i <= 100; i++) {
      dte.setTime(dte.getTime() - fiveMinutes)
      var testItem = {'Value': (Math.random() * 10).toFixed(4), 'Timestamp': dte.toUTCString()}
      dteTestData.push(testItem)
    }
    return dteTestData
  }

    /**
   * Output API error to console and result
   * @param {*} strMessage string: Error message passed from calling function
   * @param {*} error  object:  API error object
   */
  function errorHandler (strMessage, error) {
    $('#txtResult').val(strMessage + error.responseText + '\n')
    console.log(error.responseText)
    return error.status
  }

  /**
   * Create OSIjQueryDatabase AF database
   * @param {*} PIWebAPIUrl string: Location of the PI Web API instance
   * @param {*} AssetServer  string:  Name of the PI Web API Asset Server (AF)
   * @param {*} Name string: The user's credentials name
   * @param {*} Password string: The user's credentials password
   * @param {*} AuthType string: Authorization type:  basic or kerberos
   */
  function createDatabase (PIWebAPIUrl, AssetServer, Name, Password, AuthType) {
    console.clear()
    console.log('Function: createDatabase')
    var statusCode
    var data

    // Find the url to the AF asset server
    var urlFindAFAssetServer = PIWebAPIUrl + '/assetservers?path=\\\\' + AssetServer
    $('#txtAPI').val('\nGet asset server:\n' + urlFindAFAssetServer)

    $.ajax({
      type: 'GET',
      url: urlFindAFAssetServer,
      dataType: 'json',
      headers: callHeaders(Name, Password, AuthType),
      crossDomain: (authTypeKerberos(AuthType)),
      xhrFields: {
        withCredentials: (authTypeKerberos(AuthType))
      },
      success: function (response, textStatus, jqXHR) {
        // The AF server was found
        // Create the OSIjQueryDatabase database
        var urlCreateAFSampleDatabase = response['Links']['Self'] + '/assetdatabases'
        data = {'Name': databaseName,
          'Description': 'Sample Web.api database',
          'ExtendedProperties': {}
        }
        $('#txtAPI').val($('#txtAPI').val() + '\n\nCreate database:\n' + urlCreateAFSampleDatabase)
        $('#txtAPI').val($('#txtAPI').val() + '\n\ndata:\n' + JSON.stringify(data))

        $.ajax({
          type: 'POST',
          url: urlCreateAFSampleDatabase,
          contentType: 'application/json',
          headers: callHeaders(Name, Password, AuthType),
          crossDomain: (authTypeKerberos(AuthType)),
          xhrFields: {
            withCredentials: (authTypeKerberos(AuthType))
          },
          data: JSON.stringify(data),
          success: function (response, textStatus, jqXHR) {
            // OSIjQueryDatabase database was created
            $('#txtResult').val('Returned status ' + jqXHR.status + '\n')

            console.log((response === undefined || response === '' ? '' : JSON.stringify(response)) + ' OSIjQueryDatabase database created')
            statusCode = jqXHR.status
          },
          error: function (error) {
            // Error creating database
            statusCode = errorHandler('Error creating database: ', error)
          }
        })
      },
      error: function (error) {
        // Error occurred connecting to the AF server
        statusCode = errorHandler('Error finding server: ', error)
      }
    })
    return statusCode
  }

  /**
   * Create category
   * @param {*} PIWebAPIUrl string: Location of the PI Web API instance
   * @param {*} AssetServer  string:  Name of the PI Web API Asset Server (AF)
   * @param {*} Name string: The user's credentials name
   * @param {*} Password string: The user's credentials password
   * @param {*} AuthType string: Authorization type:  basic or kerberos
   */
  function createCategory (PIWebAPIUrl, AssetServer, Name, Password, AuthType) {
    console.clear()
    console.log('Function: createCategory')
    var statusCode
    var data

    // Find the OSIjQueryDatabase database
    var urlFindSampleDatabase = PIWebAPIUrl + '/assetdatabases?path=\\\\' + AssetServer + '\\' + databaseName
    $('#txtAPI').val('\nGet database:\n' + urlFindSampleDatabase)

    $.ajax({
      type: 'GET',
      url: urlFindSampleDatabase,
      dataType: 'json',
      headers: callHeaders(Name, Password, AuthType),
      crossDomain: (authTypeKerberos(AuthType)),
      xhrFields: {
        withCredentials: (authTypeKerberos(AuthType))
      },
      success: function (response, textStatus, jqXHR) {
        console.log('')
        // Create the category
        var urlCreateCategory = response['Links']['Self'] + '/elementcategories'
        data = {'Name': categoryName,
          'Description': 'Sample machine category'
        }
        $('#txtAPI').val($('#txtAPI').val() + '\n\nCreate category:\n' + urlCreateCategory)
        $('#txtAPI').val($('#txtAPI').val() + '\n\ndata:\n' + JSON.stringify(data))

        $.ajax({
          type: 'POST',
          url: urlCreateCategory,
          contentType: 'application/json',
          headers: callHeaders(Name, Password, AuthType),
          crossDomain: (authTypeKerberos(AuthType)),
          xhrFields: {
            withCredentials: (authTypeKerberos(AuthType))
          },
          data: JSON.stringify(data),
          success: function (response, textStatus, jqXHR) {
            // Category was created
            $('#txtResult').val('Returned status ' + jqXHR.status + '\n')
            console.log((response === undefined || response === '' ? '' : JSON.stringify(response)) + ' sampleMachine category created')
            statusCode = jqXHR.status
          },
          error: function (error) {
            // Error creating category
            statusCode = errorHandler('Error creating category: ', error)
          }
        })
      },
      error: function (error) {
        // Error finding OSIjQueryDatabase database
        statusCode = errorHandler('Error finding database: ', error)
      }
    })
    return statusCode
  }

  /**
   * Create an AF template
   * @param {*} PIWebAPIUrl string: Location of the PI Web API instance
   * @param {*} AssetServer  string:  Name of the PI Web API Asset Server (AF)
   * @param {*} PIServer  string:  Name of the PI Server
   * @param {*} Name string: The user's credentials name
   * @param {*} Password string: The user's credentials password
   * @param {*} AuthType string: Authorization type:  basic or kerberos
   */
  function createTemplate (PIWebAPIUrl, AssetServer, PIServer, Name, Password, AuthType) {
    console.clear()
    console.log('Function: createTemplate')
    var statusCode

    // Find the OSIjQueryDatabase database
    var urlFindSampleDatabase = PIWebAPIUrl + '/assetdatabases?path=\\\\' + AssetServer + '\\' + databaseName
    $('#txtAPI').val('\nFind the database:\n' + urlFindSampleDatabase)

    $.ajax({
      type: 'GET',
      url: urlFindSampleDatabase,
      dataType: 'json',
      headers: callHeaders(Name, Password, AuthType),
      crossDomain: (authTypeKerberos(AuthType)),
      xhrFields: {
        withCredentials: (authTypeKerberos(AuthType))
      },
      success: function (response, textStatus, jqXHR) {
        // the OSIjQueryDatabase database was found
        // Create the OSIjQueryTemplate template
        var urlCreateElementTemplate = response['Links']['Self'] + '/ElementTemplates'
        var data = {'Name': templateName,
          'Description': 'Sample Machine Template',
          'CategoryNames': [categoryName],
          'AllowElementToExtend': true}
        $('#txtAPI').val($('#txtAPI').val() + '\n\nCreate template:\n' + urlCreateElementTemplate)
        $('#txtAPI').val($('#txtAPI').val() + '\n\ndata:\n' + JSON.stringify(data))

        $.ajax({
          type: 'POST',
          url: urlCreateElementTemplate,
          contentType: 'application/json',
          headers: callHeaders(Name, Password, AuthType),
          crossDomain: (authTypeKerberos(AuthType)),
          xhrFields: {
            withCredentials: (authTypeKerberos(AuthType))
          },
          data: JSON.stringify(data),
          success: function (response, textStatus, jqXHR) {
            // The template was created
            $('#txtResult').val('Returned status ' + jqXHR.status + '\n')
            console.log((response === undefined || response === '' ? '' : JSON.stringify(response)) + ' Template OSIjQueryTemplate created')
            // Find the created template
            var urlFindMachineTemplate = PIWebAPIUrl + '/elementtemplates?path=\\\\' + AssetServer + '\\' + databaseName + '\\ElementTemplates[' + templateName + ']'
            $('#txtAPI').val($('#txtAPI').val() + '\n\nFind created template:\n' + urlFindMachineTemplate)

            $.ajax({
              type: 'GET',
              url: urlFindMachineTemplate,
              contentType: 'application/json',
              headers: callHeaders(Name, Password, AuthType),
              crossDomain: (authTypeKerberos(AuthType)),
              xhrFields: {
                withCredentials: (authTypeKerberos(AuthType))
              },
              success: function (response, textStatus, jqXHR) {
                // The created template was found
                // Create the template OSIjQueryAttributeActive attribute
                createTemplateAttributeActive(response['Links']['Self'] + '/attributetemplates', PIServer, Name, Password, AuthType)
              },
              error: function (error) {
                // Error finding the created template
                statusCode = errorHandler('Error finding created template: ', error)
              }
            })
            statusCode = jqXHR.status
          },
          error: function (error) {
            // Error creating the template
            statusCode = errorHandler('Error creating template: ', error)
          }
        })
        statusCode = jqXHR.status
      },
      error: function (error) {
        // Error finding the OSIjQueryDatabase database
        statusCode = errorHandler('Error finding database: ', error)
      }
    })
    return statusCode
  }

  /**
   * Create the AF template OSIjQueryAttributeActive attribute
   * @param {*} urlTemplateAttributes string: url of the template attributes
   * @param {*} PIServer  string:  Name of the PI Server
   * @param {*} Name string: The user's credentials name
   * @param {*} Password string: The user's credentials password
   * @param {*} AuthType string: Authorization type:  basic or kerberos
   */
  function createTemplateAttributeActive (urlTemplateAttributes, PIServer, Name, Password, AuthType) {
    var statusCode

    // Create the attribute
    var data = { 'Name': attributeActiveName,
      'Description': '',
      'IsConfigurationItem': true,
      'Type': 'Boolean'
    }
    $('#txtAPI').val($('#txtAPI').val() + '\n\nCreate template attribute:\n' + urlTemplateAttributes)
    $('#txtAPI').val($('#txtAPI').val() + '\n\ndata:\n' + JSON.stringify(data))

    $.ajax({
      type: 'POST',
      url: urlTemplateAttributes,
      contentType: 'application/json',
      headers: callHeaders(Name, Password, AuthType),
      crossDomain: (authTypeKerberos(AuthType)),
      xhrFields: {
        withCredentials: (authTypeKerberos(AuthType))
      },
      data: JSON.stringify(data),
      success: function (response, textStatus, jqXHR) {
        // The attribute was created
        // Add a tag attribute to the template
        createTemplateAttributeSinusoid(urlTemplateAttributes, PIServer, Name, Password, AuthType)
        statusCode = jqXHR.status
      },
      error: function (error) {
        // Error creating the attribute
        statusCode = errorHandler('Error creating attribute: ', error)
      }
    })
    return statusCode
  }

  /**
   * Create OSIjQueryAttributeSinusoid attribute
   * @param {*} urlTemplateAttributes string: url to template attributes
   * @param {*} PIServer  string:  Name of the PI Server
   * @param {*} Name string: The user's credentials name
   * @param {*} Password string: The user's credentials password
   * @param {*} AuthType string: Authorization type:  basic or kerberos
   */
  function createTemplateAttributeSinusoid (urlTemplateAttributes, PIServer, Name, Password, AuthType) {
    var statusCode

    // Create the attribute
    var data = {'Name': attributeSinusoidName,
      'Description': '',
      'IsConfigurationItem': false,
      'Type': 'Double',
      'DataReferencePlugIn': 'PI Point',
      'ConfigString': '\\\\' + PIServer + '\\Sinusoid'
    }
    $('#txtAPI').val($('#txtAPI').val() + '\n\nAdd template tag:\n' + urlTemplateAttributes)
    $('#txtAPI').val($('#txtAPI').val() + '\n\ndata:\n' + JSON.stringify(data))

    $.ajax({
      type: 'POST',
      url: urlTemplateAttributes,
      contentType: 'application/json',
      headers: callHeaders(Name, Password, AuthType),
      crossDomain: (authTypeKerberos(AuthType)),
      xhrFields: {
        withCredentials: (authTypeKerberos(AuthType))
      },
      data: JSON.stringify(data),
      success: createTemplateAttributeSampleTag(urlTemplateAttributes, PIServer, Name, Password, AuthType),
      error: function (error) {
        // Error creating the attribute
        statusCode = errorHandler('Error creating OSIjQueryAttributeSinusoid attribute: ', error)
      }
    })
    return statusCode
  }

  /**
   * Create OSIjQueryAttributeSampleTag attrbute
   * @param {*} urlTemplateAttributes string: url to template attributes
   * @param {*} PIServer  string:  Name of the PI Server
   * @param {*} Name string: The user's credentials name
   * @param {*} Password string: The user's credentials password
   * @param {*} AuthType string: Authorization type:  basic or kerberos
   */
  function createTemplateAttributeSampleTag (urlTemplateAttributes, PIServer, Name, Password, AuthType) {
    var statusCode

    // Create the OSIjQueryAttributeSampleTag attribute
    var data = {'Name': attributeSampleTagName,
      'Description': '',
      'IsConfigurationItem': false,
      'Type': 'Double',
      'DataReferencePlugIn': 'PI Point',
      'ConfigString': '\\\\' + PIServer + '\\%Element%_' + tagName + ';ReadOnly=False;ptclassname=classic;pointtype=Float64;pointsource=webapi'
    }
    $('#txtAPI').val($('#txtAPI').val() + '\n\nCreate template tag:\n' + urlTemplateAttributes)
    $('#txtAPI').val($('#txtAPI').val() + '\n\ndata:\n' + JSON.stringify(data))

    $.ajax({
      type: 'POST',
      url: urlTemplateAttributes,
      contentType: 'application/json',
      headers: callHeaders(Name, Password, AuthType),
      crossDomain: (authTypeKerberos(AuthType)),
      xhrFields: {
        withCredentials: (authTypeKerberos(AuthType))
      },
      data: JSON.stringify(data),
      success: function (response, textStatus, jqXHR) {
        // The OSIjQueryAttributeSampleTag attribute was created
        $('#txtResult').val('Returned status ' + jqXHR.status + '\n')
        console.log(JSON.stringify(response))
        statusCode = jqXHR.status
      },
      error: function (error) {
        // Error creating the OSIjQueryAttributeSampleTag attribute
        statusCode = errorHandler('Error creating attribute: ', error)
      }
    })
    return statusCode
  }

  /**
   * Create element
   * @param {*} PIWebAPIUrl string: Location of the PI Web API instance
   * @param {*} AssetServer  string:  Name of the PI Web API Asset Server (AF)
   * @param {*} Name string: The user's credentials name
   * @param {*} Password string: The user's credentials password
   * @param {*} AuthType string: Authorization type:  basic or kerberos
   */
  function createElement (PIWebAPIUrl, AssetServer, Name, Password, AuthType) {
    console.clear()
    console.log('Function: createElement')
    var statusCode
    var data

    // Find the OSIjQueryDatabase database
    var urlFindSampleDatabase = PIWebAPIUrl + '/assetdatabases?path=\\\\' + AssetServer + '\\' + databaseName
    $('#txtAPI').val('\nFind database:\n' + urlFindSampleDatabase)

    $.ajax({
      type: 'GET',
      url: urlFindSampleDatabase,
      dataType: 'json',
      headers: callHeaders(Name, Password, AuthType),
      crossDomain: (authTypeKerberos(AuthType)),
      xhrFields: {
        withCredentials: (authTypeKerberos(AuthType))
      },
      success: function (response, textStatus, jqXHR) {
        // Create the OSIjQueryElement element
        var urlCreateElement = response['Links']['Self'] + '/elements'
        data = {'Name': elementName,
          'Description': 'Sample equipment element',
          'TemplateName': templateName,
          'ExtendedProperties': {}
        }
        $('#txtAPI').val($('#txtAPI').val() + '\n\nCreate element:\n' + urlCreateElement)
        $('#txtAPI').val($('#txtAPI').val() + '\n\ndata:\n' + JSON.stringify(data))

        $.ajax({
          type: 'POST',
          url: urlCreateElement,
          contentType: 'application/json',
          headers: callHeaders(Name, Password, AuthType),
          crossDomain: (authTypeKerberos(AuthType)),
          xhrFields: {
            withCredentials: (authTypeKerberos(AuthType))
          },
          data: JSON.stringify(data),
          success: function (response, textStatus, jqXHR) {
            // OSIjQueryElement element created
            console.log('Equipment OSIjQueryElement created')
            var urlFindCreatedElement = PIWebAPIUrl + '/elements?path=\\\\' + AssetServer + '\\' + databaseName + '\\' + elementName
            $('#txtAPI').val('\nGet created element:\n' + urlFindCreatedElement)

            $.ajax({
              type: 'GET',
              url: urlFindCreatedElement,
              contentType: 'application/json',
              headers: callHeaders(Name, Password, AuthType),
              crossDomain: (authTypeKerberos(AuthType)),
              xhrFields: {
                withCredentials: (authTypeKerberos(AuthType))
              },
              success: function (response, textStatus, jqXHR) {
                // Created OSIjQueryElement element found
                // Create attribute tag references
                var urlCreateElementAttributeReferences = PIWebAPIUrl + '/elements/' + response['WebId'] + '/config'
                data = {'includeChildElements': true}
                $('#txtAPI').val('\nCreate element tag references:\n' + urlCreateElementAttributeReferences)
                $('#txtAPI').val($('#txtAPI').val() + '\n\ndata:\n' + JSON.stringify(data))

                $.ajax({
                  type: 'POST',
                  url: urlCreateElementAttributeReferences,
                  contentType: 'application/json',
                  headers: callHeaders(Name, Password, AuthType),
                  crossDomain: (authTypeKerberos(AuthType)),
                  xhrFields: {
                    withCredentials: (authTypeKerberos(AuthType))
                  },
                  data: JSON.stringify(data),
                  success: function (response, textStatus, jqXHR) {
                    // Tag references added based on the template configuration
                    // OSIjQueryAttributeSampleTag was created if it didn't exist
                    console.log('Created the tag references based on the template configuration')
                    statusCode = jqXHR.status
                  },
                  error: function (error) {
                    // Error creating tag references
                    statusCode = errorHandler('Error creating element tag references: ', error)
                  }
                })
              },
              error: function (error) {
                // Error finding OSIjQueryElement element
                statusCode = errorHandler('Error finding element: ', error)
              }
            })
            statusCode = jqXHR.status
          },
          error: function (error) {
            // Error creating OSIjQueryElement element
            statusCode = errorHandler('Error creating element: ', error)
          }
        })
      },
      error: function (error) {
        // Error finding sample database
        statusCode = errorHandler('Error finding database: ', error)
      }
    })
    return statusCode
  }

  /**
   * Write a single tag value
   * @param {*} PIWebAPIUrl string: Location of the PI Web API instance
   * @param {*} AssetServer  string:  Name of the PI Web API Asset Server (AF)
   * @param {*} Name string: The user's credentials name
   * @param {*} Password string: The user's credentials password
   * @param {*} AuthType string: Authorization type:  basic or kerberos
   */
  function writeSingleValue (PIWebAPIUrl, AssetServer, Name, Password, AuthType) {
    console.clear()
    console.log('Function: writeSingleValue')
    var statusCode
    var data

    var attributeValue = (Math.random() * 10).toFixed(4)

    // Find the OSIjQueryAttributeSampleTag tag
    var urlFindElementAttributeSampleTag = PIWebAPIUrl + '/attributes?path=\\\\' + AssetServer + '\\' + databaseName + '\\' + elementName + '|' + attributeSampleTagName
    $('#txtAPI').val('\nFind tag:\n' + urlFindElementAttributeSampleTag)

    $.ajax({
      type: 'GET',
      url: urlFindElementAttributeSampleTag,
      dataType: 'json',
      contentType: 'application/json',
      headers: callHeaders(Name, Password, AuthType),
      crossDomain: (authTypeKerberos(AuthType)),
      xhrFields: {
        withCredentials: (authTypeKerberos(AuthType))
      },
      success: function (response, textStatus, jqXHR) {
        // OSIjQueryAttributeSampleTag attribute was found
        // Write a value to the associated tag
        var urlUpdateSampleTagValue = response['Links']['Self'] + '/value'
        data = {'Value': attributeValue}
        $('#txtAPI').val($('#txtAPI').val() + '\n\nWrite tag value:\n' + urlUpdateSampleTagValue)
        $('#txtAPI').val($('#txtAPI').val() + '\n\ndata:\n' + JSON.stringify(data))

        $.ajax({
          type: 'PUT',
          url: urlUpdateSampleTagValue,
          dataType: 'json',
          contentType: 'application/json',
          headers: callHeaders(Name, Password, AuthType),
          crossDomain: (authTypeKerberos(AuthType)),
          xhrFields: {
            withCredentials: (authTypeKerberos(AuthType))
          },
          data: JSON.stringify(data),
          success: function (response, textStatus, jqXHR) {
            // Value was written to the tag
            console.log('Attribute OSIjQueryAttributeSampleTag write value ' + attributeValue)

            $('#txtResult').val('Returned status ' + jqXHR.status + '\n')
            statusCode = jqXHR.status
          },
          error: function (error) {
            // Error writing tag value
            statusCode = errorHandler('Error writing value: ', error)
          }
        })
      },
      error: function (error) {
        // Error finding OSIjQueryAttributeSampleTag attribute
        statusCode = errorHandler('Error finding tag: ', error)
      }
    })
    return statusCode
  }

  /**
   * Write 100 values to the OSIjQueryAttributeSampleTag attribute
   * @param {*} PIWebAPIUrl string: Location of the PI Web API instance
   * @param {*} AssetServer  string:  Name of the PI Web API Asset Server (AF)
   * @param {*} Name string: The user's credentials name
   * @param {*} Password string: The user's credentials password
   * @param {*} AuthType string: Authorization type:  basic or kerberos
   */
  function writeDataSet (PIWebAPIUrl, AssetServer, Name, Password, AuthType) {
    console.clear()
    console.log('Function: writeDataSet')
    var statusCode

    // Create the sample values
    var dataSet = createTestData()

    // Find the OSIjQueryAttributeSampleTag attribute
    var urlFindElementAttributeSampleTag = PIWebAPIUrl + '/attributes?path=\\\\' + AssetServer + '\\' + databaseName + '\\' + elementName + '|' + attributeSampleTagName
    $('#txtAPI').val('Find tag:\n' + urlFindElementAttributeSampleTag + '\n')

    $.ajax({
      type: 'GET',
      url: urlFindElementAttributeSampleTag,
      dataType: 'json',
      headers: callHeaders(Name, Password, AuthType),
      crossDomain: (authTypeKerberos(AuthType)),
      xhrFields: {
        withCredentials: (authTypeKerberos(AuthType))
      },
      success: function (response, textStatus, jqXHR) {
        // OSIjQueryAttributeSampleTag attribute was found
        // Write the sample values to the tag associated with the OSIjQueryAttributeSampleTag attribute
        var urlWriteSampleTagValues = PIWebAPIUrl + '/streams/' + response['WebId'] + '/recorded'
        $('#txtAPI').val($('#txtAPI').val() + '\nStream 100 values:\n' + urlWriteSampleTagValues)
        $('#txtAPI').val($('#txtAPI').val() + '\n\ndata:\n' + JSON.stringify(dataSet))

        $.ajax({
          type: 'POST',
          url: urlWriteSampleTagValues,
          contentType: 'application/json',
          headers: callHeaders(Name, Password, AuthType),
          crossDomain: (authTypeKerberos(AuthType)),
          xhrFields: {
            withCredentials: (authTypeKerberos(AuthType))
          },
          data: JSON.stringify(dataSet),
          success: function (response, textStatus, jqXHR) {
            // Sample values were written
            console.log('Attribute OSIjQueryAttributeSampleTag streamed 100 values')
            $('#txtResult').val('Returned status ' + jqXHR.status + '\n')
            statusCode = jqXHR.status
          },
          error: function (error) {
            // Error writing sample values
            statusCode = errorHandler('Error writing values: ', error)
          }
        })
      },
      error: function (error) {
        // Error finding the sampleTag attribute
        statusCode = errorHandler('Error finding attribute tag: ', error)
      }
    })
    return statusCode
  }

  /**
   * Update element attribute value
   * @param {*} PIWebAPIUrl string: Location of the PI Web API instance
   * @param {*} AssetServer  string:  Name of the PI Web API Asset Server (AF)
   * @param {*} Name string: The user's credentials name
   * @param {*} Password string: The user's credentials password
   * @param {*} AuthType string: Authorization type:  basic or kerberos
   */
  function updateAttributeValue (PIWebAPIUrl, AssetServer, Name, Password, AuthType) {
    console.clear()
    console.log('Function: updateAttributeValue')
    var statusCode
    var data

    // Get attribute to update
    var urlFindElementAttribute = PIWebAPIUrl + '/attributes?path=\\\\' + AssetServer + '\\' + databaseName + '\\' + elementName + '|' + attributeActiveName
    $('#txtAPI').val('\nFind attribute:\n' + urlFindElementAttribute)

    $.ajax({
      type: 'GET',
      url: urlFindElementAttribute,
      dataType: 'json',
      headers: callHeaders(Name, Password, AuthType),
      crossDomain: (authTypeKerberos(AuthType)),
      xhrFields: {
        withCredentials: (authTypeKerberos(AuthType))
      },
      success: function (response, textStatus, jqXHR) {
        // OSIjQueryAttributeActive attribute was found
        // Update the attribute value
        var urlUpdateElementAttributeValue = response['Links']['Self'] + '/value'
        data = {'Value': true}
        $('#txtAPI').val($('#txtAPI').val() + '\n\nUpdate attribute value:\n' + urlUpdateElementAttributeValue)
        $('#txtAPI').val($('#txtAPI').val() + '\n\ndata:\n' + JSON.stringify(data))

        $.ajax({
          type: 'PUT',
          url: urlUpdateElementAttributeValue,
          dataType: 'json',
          contentType: 'application/json',
          headers: callHeaders(Name, Password, AuthType),
          crossDomain: (authTypeKerberos(AuthType)),
          xhrFields: {
            withCredentials: (authTypeKerberos(AuthType))
          },
          data: JSON.stringify(data),
          success: function (response, textStatus, jqXHR) {
            // Attribute value was updated
            $('#txtResult').val('\nReturned status ' + jqXHR.status + '\n')
            console.log('Attribute OSIjQueryAttributeActive value set to true')
            statusCode = jqXHR.status
          },
          error: function (error) {
            // Error updating attribute value
            statusCode = errorHandler('Error updating attribute: ', error)
          }
        })
      },
      error: function (error) {
        // Error finding the  attribute
        statusCode = errorHandler('Error finding attribute: ', error)
      }
    })
    return statusCode
  }

  /**
   * Read attribute snapshot value
   * @param {*} PIWebAPIUrl string: Location of the PI Web API instance
   * @param {*} AssetServer  string:  Name of the PI Web API Asset Server (AF)
   * @param {*} Name string: The user's credentials name
   * @param {*} Password string: The user's credentials password
   * @param {*} AuthType string: Authorization type:  basic or kerberos
   */
  function readAttributeSnapshot (PIWebAPIUrl, AssetServer, Name, Password, AuthType) {
    console.clear()
    console.log('Function: readAttributeSnapshot')
    var statusCode

    // Find attribute OSIjQueryAttributeSampleTag
    var urlFindElementAttributeSampleTag = PIWebAPIUrl + '/attributes?path=\\\\' + AssetServer + '\\' + databaseName + '\\' + elementName + '|' + attributeSampleTagName
    $('#txtAPI').val('Find tag:\n' + urlFindElementAttributeSampleTag + '\n')

    $.ajax({
      type: 'GET',
      url: urlFindElementAttributeSampleTag,
      dataType: 'json',
      contentType: 'application/json',
      headers: callHeaders(Name, Password, AuthType),
      crossDomain: (authTypeKerberos(AuthType)),
      xhrFields: {
        withCredentials: (authTypeKerberos(AuthType))
      },
      success: function (response, textStatus, jqXHR) {
        // OSIjQueryAttributeSampleTag attribute was found
        // Get the associated tag value
        var urlGetSampleTagValue = PIWebAPIUrl + '/streams/' + response['WebId'] + '/value'
        $('#txtAPI').val($('#txtAPI').val() + '\nGet snapshot value:\n' + urlGetSampleTagValue)

        $.ajax({
          type: 'GET',
          url: urlGetSampleTagValue,
          dataType: 'json',
          contentType: 'application/json',
          headers: callHeaders(Name, Password, AuthType),
          crossDomain: (authTypeKerberos(AuthType)),
          xhrFields: {
            withCredentials: (authTypeKerberos(AuthType))
          },
          success: function (response, textStatus, jqXHR) {
            // Tag value was returned
            $('#txtResult').val('Snapshot value ' + response.Value + '\n')
            $('#txtResult').val($('#txtResult').val() + '\nResponse:\n' + JSON.stringify(response))
            $('#txtResult').val($('#txtResult').val() + '\n\nReturned status ' + jqXHR.status + '\n')

            console.log('Attribute OSIjQueryAttributeSampleTag snapshot value ' + response.Value)
            statusCode = jqXHR.status
          },
          error: function (error) {
            // Error getting tag value
            statusCode = errorHandler('Error getting tag value: ', error)
          }
        })
        statusCode = jqXHR.status
      },
      error: function (error) {
        // Error finding the sampleTag attribute
        statusCode = errorHandler('Error finding attribute tag: ', error)
      }
    })
    return statusCode
  }

  /**
   * Read tag values from a stream
   * @param {*} PIWebAPIUrl string: Location of the PI Web API instance
   * @param {*} AssetServer  string:  Name of the PI Web API Asset Server (AF)
   * @param {*} Name string: The user's credentials name
   * @param {*} Password string: The user's credentials password
   * @param {*} AuthType string: Authorization type:  basic or kerberos
   */
  function readAttributeStream (PIWebAPIUrl, AssetServer, Name, Password, AuthType) {
    console.clear()
    console.log('Function: readAttributeStream')
    var statusCode

    // Find the OSIjQueryAttributeSampleTag attribute
    var urlFindElementAttributeSampleTag = PIWebAPIUrl + '/attributes?path=\\\\' + AssetServer + '\\' + databaseName + '\\' + elementName + '|' + attributeSampleTagName
    $('#txtAPI').val('\nFind tag:\n' + urlFindElementAttributeSampleTag)

    $.ajax({
      type: 'GET',
      url: urlFindElementAttributeSampleTag,
      dataType: 'json',
      headers: callHeaders(Name, Password, AuthType),
      crossDomain: (authTypeKerberos(AuthType)),
      xhrFields: {
        withCredentials: (authTypeKerberos(AuthType))
      },
      success: function (response, textStatus, jqXHR) {
        // OSIjQueryAttributeSampleTag attribute was found
        // Get OSIjQueryAttributeSampleTag values over the last 2 days
        var urlGetSampleTagValues = PIWebAPIUrl + '/streams/' + response['WebId'] + '/recorded?startTime=*-2d'
        $('#txtAPI').val($('#txtAPI').val() + '\n\nGet values:\n' + urlGetSampleTagValues)

        $.ajax({
          type: 'GET',
          url: urlGetSampleTagValues,
          dataType: 'json',
          headers: callHeaders(Name, Password, AuthType),
          crossDomain: (authTypeKerberos(AuthType)),
          xhrFields: {
            withCredentials: (authTypeKerberos(AuthType))
          },
          success: function (response, textStatus, jqXHR) {
            // OSIjQueryAttributeSampleTag values were returned
            $('#txtResult').val('Reponse:\n' + JSON.stringify(response) + '\n')
            $('#txtResult').val($('#txtResult').val() + '\nReturned status ' + jqXHR.status + '\n')

            console.log('OSIjQueryAttributeSampleTag Values')
            $.each(response.Items, function (index, item) {
              console.log('Timestamp: ' + item.Timestamp + ' Value: ' + item.Value + ' UnitsAbbreviation: ' + item.UnitsAbbreviation +
                          ' Good: ' + item.Good + ' Questionable: ' + item.Questionable + ' Substituted: ' + item.Substituted +
                          ' Annotated: ' + item.Annotated)
            })
            statusCode = jqXHR.status
          },
          error: function (error) {
            // Error getting OSIjQueryAttributeSampleTag stream values
            statusCode = errorHandler('Error getting stream values: ', error)
          }
        })
      },
      error: function (error) {
        // Error finding the SampleTag
        statusCode = errorHandler('Error finding tag: ', error)
      }
    })
    return statusCode
  }

  /**
   * Read tag values with selected fields
   * @param {*} PIWebAPIUrl string: Location of the PI Web API instance
   * @param {*} AssetServer  string:  Name of the PI Web API Asset Server (AF)
   * @param {*} Name string: The user's credentials name
   * @param {*} Password string: The user's credentials password
   * @param {*} AuthType string: Authorization type:  basic or kerberos
   */
  function readAttributeSelectedFields (PIWebAPIUrl, AssetServer, Name, Password, AuthType) {
    console.clear()
    console.log('Function: readAttributeSelectedFields')
    var statusCode

    // Find the OSIjQueryAttributeSampleTag attribute
    var urlFindElementAttributeSampleTag = PIWebAPIUrl + '/attributes?path=\\\\' + AssetServer + '\\' + databaseName + '\\' + elementName + '|' + attributeSampleTagName
    $('#txtAPI').val('\nFind tag:\n' + urlFindElementAttributeSampleTag)

    $.ajax({
      type: 'GET',
      url: urlFindElementAttributeSampleTag,
      dataType: 'json',
      headers: callHeaders(Name, Password, AuthType),
      crossDomain: (authTypeKerberos(AuthType)),
      xhrFields: {
        withCredentials: (authTypeKerberos(AuthType))
      },
      success: function (response, textStatus, jqXHR) {
        // OSIjQueryAttributeSampleTag attribute was found
        // Get associated tag values over last two days
        var urlGetSampleTagValues = PIWebAPIUrl + '/streams/' + response['WebId'] + '/recorded?startTime=*-2d&selectedFields=Items.Timestamp;Items.Value'
        $('#txtAPI').val($('#txtAPI').val() + '\n\nGet tag values:\n' + urlGetSampleTagValues)

        $.ajax({
          type: 'GET',
          url: urlGetSampleTagValues,
          dataType: 'json',
          headers: callHeaders(Name, Password, AuthType),
          crossDomain: (authTypeKerberos(AuthType)),
          xhrFields: {
            withCredentials: (authTypeKerberos(AuthType))
          },
          success: function (response, textStatus, jqXHR) {
            // Tag values were returned
            $('#txtResult').val('Reponse:\n' + JSON.stringify(response) + '\n')
            $('#txtResult').val($('#txtResult').val() + '\nReturned status ' + jqXHR.status + '\n')

            console.log('SampleTag Values')
            $.each(response.Items, function (index, item) {
              console.log('Timestamp: ' + item.Timestamp + ' Value: ' + item.Value)
            })
            statusCode = jqXHR.status
          },
          error: function (error) {
            // Error getting tag values
            statusCode = errorHandler('Error getting tag values: ', error)
          }
        })
      },
      error: function (error) {
        // Error finding the OSIjQueryAttributeSampleTag attribute
        statusCode = errorHandler('Error finding tag: ', error)
      }
    })
    return statusCode
  }

  /**
   * Make five calls in a single batch
   * @param {*} PIWebAPIUrl string: Location of the PI Web API instance
   * @param {*} AssetServer  string:  Name of the PI Web API Asset Server (AF)
   * @param {*} Name string: The user's credentials name
   * @param {*} Password string: The user's credentials password
   * @param {*} AuthType string: Authorization type:  basic or kerberos
   */
  function doBatchCall (PIWebAPIUrl, AssetServer, Name, Password, AuthType) {
    console.clear()
    console.log('Function: doBatchCall')
    var statusCode

    // Create a single sample value
    var attributeValue = (Math.random() * 10).toFixed(4)

    // Find the OSIjQueryAttributeSampleTag attribute
    var call1 = {}
    call1['Method'] = 'GET'
    call1['Resource'] = PIWebAPIUrl + '/attributes?path=\\\\' + AssetServer + '\\' + databaseName + '\\' + elementName + '|' + attributeSampleTagName
    call1['Content'] = '{}'

    // Get snapshot value
    var call2 = {}
    call2['Method'] = 'GET'
    call2['Resource'] = PIWebAPIUrl + '/streams/{0}/value'
    call2['Content'] = '{}'
    call2['Parameters'] = ['$.1.Content.WebId']
    call2['ParentIds'] = ['1']

    // Get last 10 values
    var call3 = {}
    call3['Method'] = 'GET'
    call3['Resource'] = PIWebAPIUrl + '/streams/{0}/recorded?maxCount=10'
    call3['Content'] = '{}'
    call3['Parameters'] = ['$.1.Content.WebId']
    call3['ParentIds'] = ['1']

    // Write single value
    var call4 = {}
    call4['Method'] = 'PUT'
    call4['Resource'] = PIWebAPIUrl + '/attributes/{0}/value'
    call4['Content'] = JSON.stringify({'Value': attributeValue})
    call4['Parameters'] = ['$.1.Content.WebId']
    call4['ParentIds'] = ['1']

    // Write three values
    var call5 = {}
    call5['Method'] = 'POST'
    call5['Resource'] = PIWebAPIUrl + '/streams/{0}/recorded'
    call5['Content'] = JSON.stringify([{'Value': '111'}, {'Value': '222'}, {'Value': '333'}])
    call5['Parameters'] = ['$.1.Content.WebId']
    call5['ParentIds'] = ['1']

    // Get last 10 values with selected fields
    var call6 = {}
    call6['Method'] = 'GET'
    call6['Resource'] = PIWebAPIUrl + '/streams/{0}/recorded?maxCount=10&selectedFields=Items.Timestamp;Items.Value'
    call6['Content'] = '{}'
    call6['Parameters'] = ['$.1.Content.WebId']
    call6['ParentIds'] = ['1']

    // Add each call to the batch
    var batch = {'1': call1, '2': call2, '3': call3, '4': call4, '5': call5, '6': call6}

    // Execute the batch
    var urlExecuteBatch = PIWebAPIUrl + '/batch'
    $('#txtAPI').val($('#txtAPI').val() + '\n\nExecute batch:\n' + urlExecuteBatch)
    $('#txtAPI').val($('#txtAPI').val() + '\n\ndata:\n' + JSON.stringify(batch))

    $.ajax({
      type: 'POST',
      url: urlExecuteBatch,
      contentType: 'application/json',
      headers: callHeaders(Name, Password, AuthType),
      crossDomain: (authTypeKerberos(AuthType)),
      xhrFields: {
        withCredentials: (authTypeKerberos(AuthType))
      },
      data: JSON.stringify(batch),
      success: function (response, textStatus, jqXHR) {
        // Batch was successful
        $('#txtResult').val('Returned status ' + jqXHR.status + '\n')

        $('#txtResult').val($('#txtResult').val() + '\n1: Find sample tag\n')
        $('#txtResult').val($('#txtResult').val() + 'Status: ' + response[1].Status)
        console.log('1: Find sample tag')
        console.log('Status: ' + response[1].Status)

        $('#txtResult').val($('#txtResult').val() + '\n\n2: Get a snapshot value\n')
        $('#txtResult').val($('#txtResult').val() + 'Timestamp: ' + response[2].Content.Timestamp + ' Value: ' + response[2].Content.Value)
        console.log('2: Get a snapshot value')
        console.log('Timestamp: ' + response[2].Content.Timestamp + ' Value: ' + response[2].Content.Value)

        $('#txtResult').val($('#txtResult').val() + '\n\n3: Get a stream of recorded values\n')
        $('#txtResult').val($('#txtResult').val() + 'Items:\n' + JSON.stringify(response[3].Content.Items))
        console.log('3: Get a stream of recorded values')
        $.each(response[3].Content.Items, function (index, item) {
          console.log('Timestamp: ' + item.Timestamp + ' Value: ' + item.Value + ' UnitsAbbreviation: ' + item.UnitsAbbreviation +
                      ' Good: ' + item.Good + ' Questionable: ' + item.Questionable + ' Substituted: ' + item.Substituted +
                      ' Annotated: ' + item.Annotated)
        })

        $('#txtResult').val($('#txtResult').val() + '\n\n4: Write a single snapshot value\n')
        $('#txtResult').val($('#txtResult').val() + 'Status: ' + response[4].Status)
        console.log('5: Write a single snapshot value')
        console.log('Status: ' + response[5].Status)

        $('#txtResult').val($('#txtResult').val() + '\n\n5: Write a set of recorded data\n')
        $('#txtResult').val($('#txtResult').val() + 'Status: ' + response[5].Status)
        console.log('5: Write a set of recorded data')
        console.log('Status: ' + response[5].Status)

        $('#txtResult').val($('#txtResult').val() + '\n\n6: Reduced payloads with Selected Fields\n')
        $('#txtResult').val($('#txtResult').val() + 'Items:\n' + JSON.stringify(response[6].Content.Items))
        console.log('6: Reduced payloads with Selected Fields')
        $.each(response[6].Content.Items, function (index, item) {
          console.log('Timestamp: ' + item.Timestamp + ' Value: ' + item.Value)
        })
        statusCode = jqXHR.status
      },
      error: function (error) {
        // Error executing the batch
        statusCode = errorHandler('Error executing batch: ', error)
      }
    })

    return statusCode
  }

  /**
   * Delete element
   * @param {*} PIWebAPIUrl string: Location of the PI Web API instance
   * @param {*} AssetServer  string:  Name of the PI Web API Asset Server (AF)
   * @param {*} Name string: The user's credentials name
   * @param {*} Password string: The user's credentials password
   * @param {*} AuthType string: Authorization type:  basic or kerberos
   */
  function deleteElement (PIWebAPIUrl, AssetServer, Name, Password, AuthType) {
    console.clear()
    console.log('Function: deleteElement')
    var statusCode

    // Find the OSIjQueryElement elment to delete
    var urlFindElement = PIWebAPIUrl + '/elements?path=\\\\' + AssetServer + '\\' + databaseName + '\\' + elementName
    $('#txtAPI').val('\nFind element:\n' + urlFindElement)

    $.ajax({
      type: 'GET',
      url: urlFindElement,
      contentType: 'application/json',
      headers: callHeaders(Name, Password, AuthType),
      crossDomain: (authTypeKerberos(AuthType)),
      xhrFields: {
        withCredentials: (authTypeKerberos(AuthType))
      },
      success: function (response, textStatus, jqXHR) {
        // Delete the OSIjQueryElement element
        var urlDeleteElement = response['Links']['Self']
        $('#txtAPI').val($('#txtAPI').val() + '\n\nDelete element:\n' + urlDeleteElement)

        $.ajax({
          type: 'DELETE',
          url: urlDeleteElement,
          contentType: 'application/json',
          headers: callHeaders(Name, Password, AuthType),
          crossDomain: (authTypeKerberos(AuthType)),
          xhrFields: {
            withCredentials: (authTypeKerberos(AuthType))
          },
          success: function (response, textStatus, jqXHR) {
            // OSIjQueryElement element deleted
            $('#txtResult').val('Returned status ' + jqXHR.status + '\n')

            console.log('</br>Deleted element OSIjQueryElement')
            statusCode = jqXHR.status
          },
          error: function (error) {
            // Error deleting OSIjQueryElement element
            statusCode = errorHandler('Error deleting element: ', error)
          }
        })
      },
      error: function (error) {
        // Error finding OSIjQueryElement element
        statusCode = errorHandler('Error finding element: ', error)
      }
    })
    return statusCode
  }

  /**
   * Delete an AF template
   * @param {*} PIWebAPIUrl string: Location of the PI Web API instance
   * @param {*} AssetServer  string:  Name of the PI Web API Asset Server (AF)
   * @param {*} Name string: The user's credentials name
   * @param {*} Password string: The user's credentials password
   * @param {*} AuthType string: Authorization type:  basic or kerberos
   */
  function deleteTemplate (PIWebAPIUrl, AssetServer, Name, Password, AuthType) {
    console.clear()
    console.log('Function: deleteTemplate')
    var statusCode

    // Find template to delete
    var urlFindElementTemplate = PIWebAPIUrl + '/elementtemplates?path=\\\\' + AssetServer + '\\' + databaseName + '\\ElementTemplates[' + templateName + ']'
    $('#txtAPI').val('\nFind template:\n' + urlFindElementTemplate)

    $.ajax({
      type: 'GET',
      url: urlFindElementTemplate,
      dataType: 'json',
      headers: callHeaders(Name, Password, AuthType),
      crossDomain: (authTypeKerberos(AuthType)),
      xhrFields: {
        withCredentials: (authTypeKerberos(AuthType))
      },
      success: function (response, textStatus, jqXHR) {
        // The template was found
        // Delete the template
        var urlDeleteElementTemplate = response['Links']['Self']
        $('#txtAPI').val($('#txtAPI').val() + '\n\nDelete template:\n' + urlDeleteElementTemplate)

        $.ajax({
          type: 'DELETE',
          url: urlDeleteElementTemplate,
          dataType: 'json',
          headers: callHeaders(Name, Password, AuthType),
          crossDomain: (authTypeKerberos(AuthType)),
          xhrFields: {
            withCredentials: (authTypeKerberos(AuthType))
          },
          success: function (response, textStatus, jqXHR) {
            // The template deleted
            $('#txtResult').val('Returned status ' + jqXHR.status + '\n')
            console.log((response === undefined ? '' : JSON.stringify(response)) + ' Template OSIjQueryTemplate deleted')
            statusCode = jqXHR.status
          },
          error: function (error) {
            // Error deleting the template
            statusCode = errorHandler('Error deleting template: ', error)
          }
        })
        statusCode = jqXHR.status
      },
      error: function (error) {
        // Error finding the template
        $('#txtResult').val('Error finding template: ' + error.responseText + '\n')
        console.log(error.responseText)
        statusCode = errorHandler('Error finding template: ', error)
      }
    })
    return statusCode
  }

  /**
   * Delete category
   * @param {*} PIWebAPIUrl string: Location of the PI Web API instance
   * @param {*} AssetServer  string:  Name of the PI Web API Asset Server (AF)
   * @param {*} Name string: The user's credentials name
   * @param {*} Password string: The user's credentials password
   * @param {*} AuthType string: Authorization type:  basic or kerberos
   */
  function deleteCategory (PIWebAPIUrl, AssetServer, Name, Password, AuthType) {
    console.clear()
    console.log('Function: deleteCategory')
    var statusCode

    // Find the Equiment Assets category
    var urlFindCategory = PIWebAPIUrl + '/elementcategories?path=\\\\' + AssetServer + '\\' + databaseName + '\\CategoriesElement[' + categoryName + ']'
    $('#txtAPI').val('\nFind category:\n' + urlFindCategory)

    $.ajax({
      type: 'GET',
      url: urlFindCategory,
      dataType: 'json',
      headers: callHeaders(Name, Password, AuthType),
      crossDomain: (authTypeKerberos(AuthType)),
      xhrFields: {
        withCredentials: (authTypeKerberos(AuthType))
      },
      success: function (response, textStatus, jqXHR) {
        // Delete the category
        var urlDeleteCategory = response['Links']['Self']
        $('#txtAPI').val($('#txtAPI').val() + '\n\nDelete category:\n' + urlDeleteCategory)

        $.ajax({
          type: 'DELETE',
          url: urlDeleteCategory,
          dataType: 'json',
          headers: callHeaders(Name, Password, AuthType),
          crossDomain: (authTypeKerberos(AuthType)),
          xhrFields: {
            withCredentials: (authTypeKerberos(AuthType))
          },
          success: function (response, textStatus, jqXHR) {
            // Category was deleted
            $('#txtResult').val('Returned status ' + jqXHR.status + '\n')

            console.log((response === undefined ? '' : JSON.stringify(response)) + ' Category OSIjQueryCategory deleted')
            statusCode = jqXHR.status
          },
          error: function (error) {
            // Error deleting category
            statusCode = errorHandler('Error deleting category: ', error)
          }
        })
        statusCode = jqXHR.status
      },
      error: function (error) {
        // Error getting category
        statusCode = errorHandler('Error finding category: ', error)
      }
    })
    return statusCode
  }

  /**
   * Delete sample database
   * @param {*} PIWebAPIUrl string: Location of the PI Web API instance
   * @param {*} AssetServer  string:  Name of the PI Web API Asset Server (AF)
   * @param {*} Name string: The user's credentials name
   * @param {*} Password string: The user's credentials password
   * @param {*} AuthType string: Authorization type:  basic or kerberos
   */
  function deleteDatabase (PIWebAPIUrl, AssetServer, Name, Password, AuthType) {
    console.clear()
    console.log('Function: deleteDatabase')
    var statusCode

    // Find the OSIjQueryDatabase database
    var urlFindSampleDatabase = PIWebAPIUrl + '/assetdatabases?path=\\\\' + AssetServer + '\\' + databaseName
    $('#txtAPI').val('\nFind database:\n' + urlFindSampleDatabase)

    $.ajax({
      type: 'GET',
      url: urlFindSampleDatabase,
      dataType: 'json',
      headers: callHeaders(Name, Password, AuthType),
      crossDomain: (authTypeKerberos(AuthType)),
      xhrFields: {
        withCredentials: (authTypeKerberos(AuthType))
      },
      success: function (response, textStatus, jqXHR) {
        // the OSIjQueryDatabase database was found
        // Delete the OSIjQueryDatabase database
        var urlDeleteSampleDatabase = PIWebAPIUrl + '/assetdatabases/' + response['WebId']
        $('#txtAPI').val($('#txtAPI').val() + '\n\nDelete database:\n' + urlDeleteSampleDatabase)
        $.ajax({
          type: 'DELETE',
          url: urlDeleteSampleDatabase,
          dataType: 'json',
          headers: callHeaders(Name, Password, AuthType),
          crossDomain: (authTypeKerberos(AuthType)),
          xhrFields: {
            withCredentials: (authTypeKerberos(AuthType))
          },
          success: function (response, textStatus, jqXHR) {
            // OSIjQueryDatabase database deleted
            $('#txtResult').val('Returned status ' + jqXHR.status + '\n')
            console.log((response === undefined ? '' : JSON.stringify(response)) + ' OSIjQueryDatabase database deleted')
            statusCode = jqXHR.status
          },
          error: function (error) {
            // Error deleting OSIjQueryDatabase database
            statusCode = errorHandler('Error deleting database: ', error)
          }
        })
        statusCode = jqXHR.status
      },
      error: function (error) {
        // Error finding OSIjQueryDatabase database
        statusCode = errorHandler('Error finding database: ', error)
      }
    })
    return statusCode
  }
