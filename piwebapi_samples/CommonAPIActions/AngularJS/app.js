/* eslint-disable linebreak-style */
'use strict';

/**
 * To run the application:
 *   npm start
 *
 * "npm start" should automatically call "npm install".
 * If not, run "npm install" to install the application dependencies.
 */

// Declare app level module which depends on views, and core components.
const myApp = angular.module('myApp', []);

myApp.controller('AppController', function AppController($scope, $http, $q) {
  $scope.callOptions = [
    { id: 'createDatabase', name: 'Create Database' },
    { id: 'createcategory', name: 'Create Category' },
    { id: 'createtemplate', name: 'Create Template' },
    { id: 'createelement', name: 'Create Element' },
    { id: 'divider', name: '-----------------------' },
    { id: 'writesinglevalue', name: 'Write Single Value' },
    { id: 'writerecordedvalues', name: 'Write Set of Values' },
    { id: 'updatevalue', name: 'Update Attribute Value' },
    { id: 'getsnapshotvalue', name: 'Get Single Value' },
    { id: 'getrecordedvalues', name: 'Get Set of Values' },
    {
      id: 'payloadselectedfields',
      name: 'Reduce Payload with Selected Fields',
    },
    { id: 'batch', name: 'Batch Writes and Reads' },
    { id: 'divider', name: '-----------------------' },
    { id: 'deleteelement', name: 'Delete Element' },
    { id: 'deletetemplate', name: 'Delete Template' },
    { id: 'deletecategory', name: 'Delete Category' },
    { id: 'deletedatabase', name: 'Delete Database' },
  ];

  $scope.piWebAPIUrl = '';
  $scope.assetServer = '';
  $scope.piServerName = '';
  $scope.userName = '';
  $scope.userPassword = '';
  $scope.securityMethod = '';
  $scope.selectedCallOption = '';
  $scope.codeResult = '';
  $scope.callURIText = '';
  $scope.returnCode = 0;

  // Define string constants for the results we're interested in.
  $scope.resultBody = 'data';
  $scope.resultLinks = 'Links';
  $scope.resultValue = 'Value';
  $scope.resultSelf = 'Self';
  $scope.resultWebId = 'WebId';
  $scope.returnStatus = 'status';
  $scope.statusText = 'statusText';

  // Define string constants for the AF objects created for the sandbox.
  $scope.databaseName = 'OSIAngularJSDatabase';
  $scope.categoryName = 'OSIAngularJSCategory';
  $scope.templateName = 'OSIAngularJSTemplate';
  $scope.elementName = 'OSIAngularJSElement';
  $scope.activeAttributeName = 'OSIAngularJSAttributeActive';
  $scope.sinusoidUAttributeName = 'OSIAngularJSAttributeSinusoidU';
  $scope.sinusoidAttributeName = 'OSIAngularJSAttributeSinusoid';
  $scope.sampleTagName = 'OSIAngularJSSampleTag';
  $scope.sampleTagAttributeName = 'OSIAngularJSAttributeSampleTag';

  $scope.securityMethods = [
    { id: 'basic', name: 'Basic' },
    { id: 'kerberos', name: 'Kerberos' },
  ];

  /**
   * Create API call headers based on authorization type.
   * @param {string} userName The user's credentials name.
   * @param {string} userPassword The user's credentials password.
   * @param {string} authType Authorization type: Basic or Kerberos.
   * @return {object} The headers for the http request.
   */
  $scope.callHeaders = function (userName, userPassword, authType) {
    let callHeaders;

    if (authType === 'kerberos') {
      // Build a kerberos authentication header.
      callHeaders = {
        'X-Requested-With': 'XmlHttpRequest',
      };
    } else {
      // Build a basic authentication header.
      callHeaders = {
        'X-Requested-With': 'XmlHttpRequest',
        Authorization: 'Basic ' + btoa(userName + ':' + userPassword),
      };
    }
    return callHeaders;
  };

  /**
   * Create sample data used by subsequent calls.
   * @return {Array} Random test data.
   */
  $scope.createTestData = function () {
    const dteTestData = [];
    const fiveMinutes = 5 * 60 * 1000;
    const dte = new Date(new Date().setHours(0, 0, 0, 0));
    dte.setDate(dte.getDate() - 2);
    for (let i = 1; i <= 100; i++) {
      dte.setTime(dte.getTime() - fiveMinutes);
      const testItem = {
        Value: (Math.random() * 10).toFixed(4),
        Timestamp: dte.toUTCString(),
      };
      dteTestData.push(testItem);
    }
    return dteTestData;
  };

  /**
   * Create a sample Web API database.
   * @param {string} piWebAPIUrl Location of the PI Web API instance.
   * @param {string} assetServer Name of the PI Web API Asset Server (AF).
   * @param {string} userName The user's credentials name.
   * @param {string} userPassword The user's credentials password.
   * @param {string} authType The authentication type (basic or kerberos).
   * @return {number} The return code of the last PI Web API request.
   */
  $scope.createDatabase = function (
    piWebAPIUrl,
    assetServer,
    userName,
    userPassword,
    authType
  ) {
    try {
      // Create the header and URI for the GET request.
      const httpOptions = $scope.callHeaders(userName, userPassword, authType);
      let callURI = piWebAPIUrl + '/assetservers?path=\\\\' + assetServer;

      // Write the URI we're about to call to the textarea in the UI.
      $scope.callURIText =
        'GET request URI to retrieve the Asset Server: ' + callURI;

      // Get the asset server.
      return $scope
        .makeGETRequest(callURI, httpOptions, authType)
        .then(function (result) {
          // Construct the request body.
          const requestBody = {
            Name: $scope.databaseName,
            Description: 'Database for OSI AngularJS Web API Sample',
            ExtendedProperties: {},
          };
          // Build the next URI for the POST request.
          callURI =
            result[$scope.resultBody][$scope.resultLinks][$scope.resultSelf] +
            '/assetdatabases';

          // Write the URI we're about to call to the textarea in the UI.
          $scope.callURIText +=
            '\nPOST request URI to create the database: ' + callURI;
          $scope.callURIText +=
            '\n\nPOST request body:\n' + JSON.stringify(requestBody, null, 2);

          // Make a POST request to create the database.
          return $scope.makePOSTRequest(
            callURI,
            httpOptions,
            requestBody,
            authType
          );
        })
        .then(function (result) {
          $scope.returnCode = result[$scope.returnStatus];
          $scope.codeResult = 'Database ' + $scope.databaseName + ' created';
          return $scope.returnCode;
        })
        .catch(function (response) {
          $scope.returnCode = response.status;
          $scope.codeResult = 'An error occurred. ' + response.statusText;
          return $scope.returnCode;
        });
    } catch (e) {
      console.log('error ' + e);
      $scope.codeResult = e.message;
    }
  };

  /**
   * Create an AF Category.
   * @param {string} piWebAPIUrl Location of the PI Web API instance.
   * @param {string} assetServer Name of the PI Web API Asset Server (AF).
   * @param {string} userName The user's credentials name.
   * @param {string} userPassword The user's credentials password.
   * @param {string} authType The authentication type (basic or kerberos).
   * @return {number} The return code of the last PI Web API request.
   */
  $scope.createCategory = function (
    piWebAPIUrl,
    assetServer,
    userName,
    userPassword,
    authType
  ) {
    try {
      // Create the header and URI for the GET request.
      const httpOptions = $scope.callHeaders(userName, userPassword, authType);
      let callURI =
        piWebAPIUrl +
        '/assetdatabases?path=\\\\' +
        assetServer +
        '\\' +
        $scope.databaseName;

      // Write the URI we're about to call to the textarea in the UI.
      $scope.callURIText =
        'GET Request URI to retrieve the database: ' + callURI;

      // Get the asset server database.
      return $scope
        .makeGETRequest(callURI, httpOptions, authType)
        .then(function (result) {
          // Construct the request body.
          const requestBody = {
            Name: $scope.categoryName,
            Description: 'Sample ' + $scope.templateName + ' category',
          };

          // Build the next URI for the POST request.
          callURI =
            result[$scope.resultBody][$scope.resultLinks][$scope.resultSelf] +
            '/elementcategories';

          // Write the URI we're about to call to the textarea in the UI.
          $scope.callURIText +=
            '\nPOST request URI to create the category: ' + callURI;
          $scope.callURIText +=
            '\n\nPOST request body:\n' + JSON.stringify(requestBody, null, 2);

          // Make a POST request to create the category.
          return $scope.makePOSTRequest(
            callURI,
            httpOptions,
            requestBody,
            authType
          );
        })
        .then(function (result) {
          $scope.returnCode = result[$scope.returnStatus];
          $scope.codeResult = 'Category ' + $scope.categoryName + ' created';
          return $scope.returnCode;
        })
        .catch(function (response) {
          $scope.returnCode = response.status;
          $scope.codeResult = 'An error occurred. ' + response.statusText;
          return $scope.returnCode;
        });
    } catch (e) {
      console.log(e);
      $scope.codeResult = e.message;
    }
  };

  /**
   * Create an AF Template.
   * @param {string} piWebAPIUrl Location of the PI Web API instance.
   * @param {string} assetServer Name of the PI Web API Asset Server (AF).
   * @param {string} piServer Name of the PI Server.
   * @param {string} userName The user's credentials name.
   * @param {string} userPassword The user's credentials password.
   * @param {string} authType The authentication type (basic or kerberos).
   * @return {number} The return code of the last PI Web API request.
   */
  $scope.createTemplate = function (
    piWebAPIUrl,
    assetServer,
    piServer,
    userName,
    userPassword,
    authType
  ) {
    try {
      // Create the header and URI for the GET request.
      const httpOptions = $scope.callHeaders(userName, userPassword, authType);
      let callURI =
        piWebAPIUrl +
        '/assetdatabases?path=\\\\' +
        assetServer +
        '\\' +
        $scope.databaseName;

      // Write the URI we're about to call to the textarea in the UI.
      $scope.callURIText =
        'GET Request URI to retrieve the database: ' + callURI;

      // Get the asset server database.
      return $scope
        .makeGETRequest(callURI, httpOptions, authType)
        .then(function (result) {
          // Construct the request body.
          const requestBody = {
            Name: $scope.templateName,
            Description: 'Sample ' + $scope.templateName + ' Template',
            CategoryNames: [$scope.categoryName],
            AllowElementToExtend: true,
          };

          // Build the next URI for the POST request.
          callURI =
            result[$scope.resultBody][$scope.resultLinks][$scope.resultSelf] +
            '/elementtemplates';

          // Write the URI we're about to call to the textarea in the UI.
          $scope.callURIText +=
            '\nPOST request URI to create the template: ' + callURI;
          $scope.callURIText +=
            '\n\nPOST request body:\n' + JSON.stringify(requestBody, null, 2);

          // Make a POST request to create the AF template.
          return $scope.makePOSTRequest(
            callURI,
            httpOptions,
            requestBody,
            authType
          );
        })
        .then(function (result) {
          $scope.codeResult = 'Element Template created';

          // Write the URI we're about to call to the textarea in the UI.
          callURI =
            piWebAPIUrl +
            '/elementtemplates?path=\\\\' +
            assetServer +
            '\\' +
            $scope.databaseName +
            '\\ElementTemplates[' +
            $scope.templateName +
            ']';
          $scope.callURIText +=
            '\n\nGET Request URI to retrieve the newly created template: ' +
            callURI;

          // Get the newly created machine template.
          return $scope.makeGETRequest(callURI, httpOptions, authType);
        })
        .then(function (machine) {
          callURI =
            machine[$scope.resultBody][$scope.resultLinks][$scope.resultSelf] +
            '/attributetemplates';

          // Write the URI we're about to call to the textarea in the UI.
          $scope.callURIText +=
            '\nPOST Request URI to create an attribute: ' + callURI;
          $scope.callURIText +=
            '\n\nPOST ' +
            $scope.templateName +
            ' attribute request body:\n' +
            JSON.stringify(
              {
                Name: $scope.activeAttributeName,
                Description: '',
                IsConfigurationItem: true,
                Type: 'Boolean',
              },
              null,
              2
            );

          // Add template attribute.
          return $scope.makePOSTRequest(
            callURI,
            httpOptions,
            {
              Name: $scope.activeAttributeName,
              Description: '',
              IsConfigurationItem: true,
              Type: 'Boolean',
            },
            authType
          );
        })
        .then(function (result) {
          $scope.codeResult +=
            '\n' + $scope.activeAttributeName + ' attribute template created';

          // Write the URI we're about to call to the textarea in the UI.
          $scope.callURIText +=
            '\n\nPOST OS attribute request body:\n' +
            JSON.stringify(
              {
                Name: 'OS',
                Description: 'Operating System',
                IsConfigurationItem: true,
                Type: 'String',
              },
              null,
              2
            );

          // Add template attribute:  OS.
          return $scope.makePOSTRequest(
            callURI,
            httpOptions,
            {
              Name: 'OS',
              Description: 'Operating System',
              IsConfigurationItem: true,
              Type: 'String',
            },
            authType
          );
        })
        .then(function (result) {
          $scope.codeResult += '\nOS attribute template created';

          // Write the URI we're about to call to the textarea in the UI.
          $scope.callURIText +=
            '\n\nPOST OSVersion attribute request body:\n' +
            JSON.stringify(
              {
                Name: 'OSVersion',
                Description: 'Operating System Version',
                IsConfigurationItem: true,
                Type: 'String',
              },
              null,
              2
            );

          // Add template attribute:  OSVersion.
          return $scope.makePOSTRequest(
            callURI,
            httpOptions,
            {
              Name: 'OSVersion',
              Description: 'Operating System Version',
              IsConfigurationItem: true,
              Type: 'String',
            },
            authType
          );
        })
        .then(function (result) {
          $scope.codeResult += '\nOSVersion attribute template created';

          // Write the URI we're about to call to the textarea in the UI.
          $scope.callURIText +=
            '\n\nPOST IPAddress attribute request body:\n' +
            JSON.stringify(
              {
                Name: 'IPAddresses',
                Description:
                  'A list of IP Addresses for all NIC in the machine',
                IsConfigurationItem: true,
                Type: 'String',
              },
              null,
              2
            );

          // Add template attribute:  OSVersion.
          return $scope.makePOSTRequest(
            callURI,
            httpOptions,
            {
              Name: 'IPAddresses',
              Description: 'A list of IP Addresses for all NIC in the machine',
              IsConfigurationItem: true,
              Type: 'String',
            },
            authType
          );
        })
        .then(function (result) {
          $scope.codeResult += '\nIPAddresses attribute template created';

          // Write the URI we're about to call to the textarea in the UI.
          $scope.callURIText +=
            '\n\nPOST ' +
            $scope.sinusoidUAttributeName +
            ' attribute request body:\n' +
            JSON.stringify(
              {
                Name: $scope.sinusoidUAttributeName,
                Description: '',
                IsConfigurationItem: false,
                Type: 'Double',
                DataReferencePlugIn: 'PI Point',
                ConfigString: '\\\\' + piServer + '\\SinusoidU',
              },
              null,
              2
            );

          // Add Sinusoid U.
          return $scope.makePOSTRequest(
            callURI,
            httpOptions,
            {
              Name: $scope.sinusoidUAttributeName,
              Description: '',
              IsConfigurationItem: false,
              Type: 'Double',
              DataReferencePlugIn: 'PI Point',
              ConfigString: '\\\\' + piServer + '\\SinusoidU',
            },
            authType
          );
        })
        .then(function (result) {
          $scope.codeResult +=
            '\n' +
            $scope.sinusoidUAttributeName +
            ' attribute template created';

          //  Write the URI we're about to call to the textarea in the UI
          $scope.callURIText +=
            '\n\nPOST ' +
            $scope.sinusoidAttributeName +
            ' attribute request body:\n' +
            JSON.stringify(
              {
                Name: $scope.sinusoidAttributeName,
                Description: '',
                IsConfigurationItem: false,
                Type: 'Double',
                DataReferencePlugIn: 'PI Point',
                ConfigString: '\\\\' + piServer + '\\Sinusoid',
              },
              null,
              2
            );

          // Add Sinusoid.
          return $scope.makePOSTRequest(
            callURI,
            httpOptions,
            {
              Name: $scope.sinusoidAttributeName,
              Description: '',
              IsConfigurationItem: false,
              Type: 'Double',
              DataReferencePlugIn: 'PI Point',
              ConfigString: '\\\\' + piServer + '\\Sinusoid',
            },
            authType
          );
        })
        .then(function (result) {
          $scope.codeResult +=
            '\n' + $scope.sinusoidAttributeName + ' attribute template created';

          // Write the URI we're about to call to the textarea in the UI.
          $scope.callURIText +=
            '\n\nPOST ' +
            $scope.sampleTagAttributeName +
            ' attribute request body:\n' +
            JSON.stringify(
              {
                Name: $scope.sampleTagAttributeName,
                Description: '',
                IsConfigurationItem: false,
                Type: 'Double',
                DataReferencePlugIn: 'PI Point',
                ConfigString:
                  '\\\\' +
                  piServer +
                  '\\%Element%_' +
                  $scope.sampleTagName +
                  ';ReadOnly=False;ptclassname=classic;pointtype=Float64;pointsource=webapi',
              },
              null,
              2
            );

          // Add the sampleTag attribute.
          return $scope.makePOSTRequest(
            callURI,
            httpOptions,
            {
              Name: $scope.sampleTagAttributeName,
              Description: '',
              IsConfigurationItem: false,
              Type: 'Double',
              DataReferencePlugIn: 'PI Point',
              ConfigString:
                '\\\\' +
                piServer +
                '\\%Element%_' +
                $scope.sampleTagName +
                ';ReadOnly=False;ptclassname=classic;pointtype=Float64;pointsource=webapi',
            },
            authType
          );
        })
        .then(function (result) {
          $scope.returnCode = result[$scope.returnStatus];
          $scope.codeResult +=
            '\n' +
            $scope.sampleTagAttributeName +
            ' attribute template created';
          return $scope.returnCode;
        })
        .catch(function (response) {
          $scope.returnCode = response.status;
          $scope.codeResult = 'An error occurred. ' + response.statusText;
          return $scope.returnCode;
        });
    } catch (e) {
      console.log('An error occurred: ' + e);
      $scope.codeResult = e.message;
    }
  };

  /**
   * Create an AF Element.
   * @param {string} piWebAPIUrl Location of the PI Web API instance.
   * @param {string} assetServer Name of the PI Web API Asset Server (AF).
   * @param {string} userName The user's credentials name.
   * @param {string} userPassword The user's credentials password.
   * @param {string} authType The authentication type (basic or kerberos).
   * @return {number} The return code of the last PI Web API request.
   */
  $scope.createElement = function (
    piWebAPIUrl,
    assetServer,
    userName,
    userPassword,
    authType
  ) {
    try {
      // Create the header and URI for the GET request.
      const httpOptions = $scope.callHeaders(userName, userPassword, authType);
      let callURI =
        piWebAPIUrl +
        '/assetdatabases?path=\\\\' +
        assetServer +
        '\\' +
        $scope.databaseName;

      // Write the URI we're about to call to the textarea in the UI.
      $scope.callURIText =
        'GET Request URI to retrieve the database: ' + callURI;

      // Get the asset server database.
      return $scope
        .makeGETRequest(callURI, httpOptions, authType)
        .then(function (result) {
          //  construct the request body
          const requestBody = {
            Name: $scope.elementName,
            Description: $scope.elementName + ' element',
            TemplateName: $scope.templateName,
            ExtendedProperties: {},
          };

          // Build the next URI for the POST request.
          callURI =
            result[$scope.resultBody][$scope.resultLinks][$scope.resultSelf] +
            '/elements';

          // Write the URI we're about to call to the textarea in the UI.
          $scope.callURIText +=
            '\nPOST request URI to create the element: ' + callURI;
          $scope.callURIText +=
            '\n\nPOST request body:\n' + JSON.stringify(requestBody, null, 2);

          // Make a POST request to create the element.
          return $scope.makePOSTRequest(
            callURI,
            httpOptions,
            requestBody,
            authType
          );
        })
        .then(function (result) {
          $scope.codeResult = 'Equipment ' + $scope.elementName + ' created';

          callURI =
            piWebAPIUrl +
            '/elements?path=\\\\' +
            assetServer +
            '\\' +
            $scope.databaseName +
            '\\' +
            $scope.elementName;

          // Write the URI we're about to call to the textarea in the UI.
          $scope.callURIText +=
            '\n\nGET Request URI to get the newly created element: ' + callURI;

          // Get the newly created element.
          return $scope.makeGETRequest(callURI, httpOptions, authType);
        })
        .then(function (elementResponse) {
          callURI =
            piWebAPIUrl +
            '/elements/' +
            elementResponse[$scope.resultBody][$scope.resultWebId] +
            '/config';

          // Write the URI we're about to call to the textarea in the UI.
          $scope.callURIText +=
            '\nPOST Request URI to create tags based on the template configuration: ' +
            callURI;
          $scope.callURIText +=
            '\n\nPOST request body:\n' +
            JSON.stringify({ includeChildElements: true }, null, 2);

          // Create the tags based on the template configuration.
          return $scope.makePOSTRequest(
            callURI,
            httpOptions,
            { includeChildElements: true },
            authType
          );
        })
        .then(function (result) {
          $scope.returnCode = result[$scope.returnStatus];
          $scope.codeResult = 'Element tags created';
          return $scope.returnCode;
        })
        .catch(function (response) {
          $scope.returnCode = response.status;
          $scope.codeResult = 'An error occurred. ' + response.statusText;
          return $scope.returnCode;
        });
    } catch (e) {
      console.log(e);
      $scope.codeResult = e.message;
    }
  };

  /**
   * Write a single value to the sampleTag.
   * @param {string} piWebAPIUrl Location of the PI Web API instance.
   * @param {string} assetServer Name of the PI Web API Asset Server (AF).
   * @param {string} userName The user's credentials name.
   * @param {string} userPassword The user's credentials password.
   * @param {string} authType The authentication type (basic or kerberos).
   * @return {number} The return code of the last PI Web API request.
   */
  $scope.writeSingleValue = function (
    piWebAPIUrl,
    assetServer,
    userName,
    userPassword,
    authType
  ) {
    // Create a random number to use are our value and construct a requestbody using that value.
    const dataValue = Math.floor(Math.random() * 100) + 1;

    try {
      // Create the header and URI for the GET request.
      const httpOptions = $scope.callHeaders(userName, userPassword, authType);
      let callURI =
        piWebAPIUrl +
        '/attributes?path=\\\\' +
        assetServer +
        '\\' +
        $scope.databaseName +
        '\\' +
        $scope.elementName +
        '|' +
        $scope.sampleTagAttributeName;

      // Write the URI we're about to call to the textarea in the UI.
      $scope.callURIText =
        'GET Request URI to retrieve the SampleTag: ' + callURI;

      // Get the sample tag.
      return $scope
        .makeGETRequest(callURI, httpOptions, authType)
        .then(function (result) {
          // Construct the request body.
          const requestBody = {
            Value: dataValue,
          };

          // Build the next URI for the POST request.
          callURI =
            result[$scope.resultBody][$scope.resultLinks][$scope.resultValue];

          // Write the URI we're about to call to the textarea in the UI.
          $scope.callURIText +=
            '\nPOST Request URI to write the single value: ' + callURI;
          $scope.callURIText +=
            '\n\nPOST request body:\n' + JSON.stringify(requestBody, null, 2);

          // Make a POST request to write the random number to the tag.
          return $scope.makePOSTRequest(
            callURI,
            httpOptions,
            requestBody,
            authType
          );
        })
        .then(function (result) {
          $scope.returnCode = result[$scope.returnStatus];
          $scope.codeResult =
            'Attribute ' +
            $scope.sampleTagAttributeName +
            ' write value: ' +
            dataValue;
          return $scope.returnCode;
        })
        .catch(function (response) {
          $scope.returnCode = response.status;
          $scope.codeResult = 'An error occurred. ' + response.statusText;
          return $scope.returnCode;
        });
    } catch (e) {
      console.log(e);
      $scope.codeResult = e.message;
    }
  };

  /**
   * Write a set of recorded values to the sampleTag
   * @param {string} piWebAPIUrl Location of the PI Web API instance.
   * @param {string} assetServer Name of the PI Web API Asset Server (AF).
   * @param {string} userName The user's credentials name.
   * @param {string} userPassword The user's credentials password.
   * @param {string} authType The authentication type (basic or kerberos).
   * @return {number} The return code of the last PI Web API request.
   */
  $scope.writeSetOfValues = function (
    piWebAPIUrl,
    assetServer,
    userName,
    userPassword,
    authType
  ) {
    try {
      // Create the header and URI for the GET request.
      const httpOptions = $scope.callHeaders(userName, userPassword, authType);
      let callURI =
        piWebAPIUrl +
        '/attributes?path=\\\\' +
        assetServer +
        '\\' +
        $scope.databaseName +
        '\\' +
        $scope.elementName +
        '|' +
        $scope.sampleTagAttributeName;

      // Write the URI we're about to call to the textarea in the UI.
      $scope.callURIText =
        'GET Request URI to retrieve the SampleTag: ' + callURI;

      // Get the sample tag.
      return $scope
        .makeGETRequest(callURI, httpOptions, authType)
        .then(function (result) {
          // .Create some data to use in the call
          const requestBody = $scope.createTestData();

          // Build the next URI for the POST request.
          callURI =
            piWebAPIUrl +
            '/streams/' +
            result[$scope.resultBody][$scope.resultWebId] +
            '/recorded';

          // Write the URI we're about to call to the textarea in the UI.
          $scope.callURIText +=
            '\nPOST Request URI to write the data to the tag: ' + callURI;
          $scope.callURIText +=
            '\n\nPOST request body:\n' + JSON.stringify(requestBody, null, 2);

          // Make a POST request to write the dataset to the recorded streams.
          return $scope.makePOSTRequest(
            callURI,
            httpOptions,
            requestBody,
            authType
          );
        })
        .then(function (result) {
          $scope.returnCode = result[$scope.returnStatus];
          $scope.codeResult =
            'Attribute ' +
            $scope.sampleTagAttributeName +
            ' streamed 100 values: ';
          return $scope.returnCode;
        })
        .catch(function (response) {
          $scope.returnCode = response.status;
          $scope.codeResult = 'An error occurred. ' + response.statusText;
          return $scope.returnCode;
        });
    } catch (e) {
      console.log(e);
      $scope.codeResult = e.message;
    }
  };

  /**
   * Update the Active attribute for the sample tag.
   * @param {string} piWebAPIUrl Location of the PI Web API instance.
   * @param {string} assetServer Name of the PI Web API Asset Server (AF).
   * @param {string} userName The user's credentials name.
   * @param {string} userPassword The user's credentials password.
   * @param {string} authType The authentication type (basic or kerberos).
   * @return {number} The return code of the last PI Web API request.
   */
  $scope.updateAttributeValue = function (
    piWebAPIUrl,
    assetServer,
    userName,
    userPassword,
    authType
  ) {
    try {
      // Create the header and URI for the GET request.
      const httpOptions = $scope.callHeaders(userName, userPassword, authType);
      let callURI =
        piWebAPIUrl +
        '/attributes?path=\\\\' +
        assetServer +
        '\\' +
        $scope.databaseName +
        '\\' +
        $scope.elementName +
        '|' +
        $scope.activeAttributeName;

      // Write the URI we're about to call to the textarea in the UI.
      $scope.callURIText =
        'GET Request URI to retrieve the ' +
        $scope.activeAttributeName +
        ' attribute: ' +
        callURI;

      // Get the active attribute for the sample tag.
      return $scope
        .makeGETRequest(callURI, httpOptions, authType)
        .then(function (result) {
          // Create some data to use in the call.
          const requestBody = {
            Value: true,
          };

          // Build the next URI for the POST request.
          callURI =
            result[$scope.resultBody][$scope.resultLinks][$scope.resultValue];

          // Write the URI we're about to call to the textarea in the UI.
          $scope.callURIText +=
            '\nPUT Request URI to update the ' +
            $scope.activeAttributeName +
            ' attribute value: ' +
            callURI;
          $scope.callURIText +=
            '\n\nPUT request body:\n' + JSON.stringify(requestBody, null, 2);

          // Make a PUT request to write the dataset to the recorded streams.
          return $scope.makePUTRequest(
            callURI,
            httpOptions,
            requestBody,
            authType
          );
        })
        .then(function (result) {
          $scope.returnCode = result[$scope.returnStatus];
          $scope.codeResult =
            'Attribute ' + $scope.activeAttributeName + ' value set to true';
          return $scope.returnCode;
        })
        .catch(function (response) {
          $scope.returnCode = response.status;
          $scope.codeResult = 'An error occurred. ' + response.statusText;
          return $scope.returnCode;
        });
    } catch (e) {
      console.log(e);
      $scope.codeResult = e.message;
    }
  };

  /**
   * Read snapshot value.
   * @param {string} piWebAPIUrl Location of the PI Web API instance.
   * @param {string} assetServer Name of the PI Web API Asset Server (AF).
   * @param {string} userName The user's credentials name.
   * @param {string} userPassword The user's credentials password.
   * @param {string} authType The authentication type (basic or kerberos).
   * @return {number} The return code of the last PI Web API request.
   */
  $scope.readSingleValue = function (
    piWebAPIUrl,
    assetServer,
    userName,
    userPassword,
    authType
  ) {
    try {
      // Create the header and URI for the GET request.
      const httpOptions = $scope.callHeaders(userName, userPassword, authType);
      let callURI =
        piWebAPIUrl +
        '/attributes?path=\\\\' +
        assetServer +
        '\\' +
        $scope.databaseName +
        '\\' +
        $scope.elementName +
        '|' +
        $scope.sampleTagAttributeName;

      // Write the URI we're about to call to the textarea in the UI.
      $scope.callURIText =
        'GET Request URI to retrieve the ' +
        $scope.sampleTagAttributeName +
        ': ' +
        callURI;

      // Get the sample tag.
      return $scope
        .makeGETRequest(callURI, httpOptions, authType)
        .then(function (result) {
          // Build the next URI for the POST request.
          callURI =
            piWebAPIUrl +
            '/streams/' +
            result[$scope.resultBody][$scope.resultWebId] +
            '/value';

          // Write the URI we're about to call to the textarea in the UI.
          $scope.callURIText +=
            '\nGET Request URI to retrieve the snapshot value: ' + callURI;

          // Make a get request to retrieve the snapshot value.
          return $scope.makeGETRequest(callURI, httpOptions, authType);
        })
        .then(function (result) {
          $scope.returnCode = result[$scope.returnStatus];
          $scope.codeResult =
            $scope.sampleTagAttributeName +
            ' Snapshot Value: ' +
            result[$scope.resultBody][$scope.resultValue];
          return $scope.returnCode;
        })
        .catch(function (response) {
          $scope.returnCode = response.status;
          $scope.codeResult = 'An error occurred. ' + response.statusText;
          return $scope.returnCode;
        });
    } catch (e) {
      console.log(e);
      $scope.codeResult = e.message;
    }
  };

  /**
   * Read an attribute stream
   * @param {string} piWebAPIUrl Location of the PI Web API instance.
   * @param {string} assetServer Name of the PI Web API Asset Server (AF).
   * @param {string} userName The user's credentials name.
   * @param {string} userPassword The user's credentials password.
   * @param {string} authType The authentication type (basic or kerberos).
   * @return {number} The return code of the last PI Web API request.
   */
  $scope.readSetOfValues = function (
    piWebAPIUrl,
    assetServer,
    userName,
    userPassword,
    authType
  ) {
    try {
      // Create the header and URI for the GET request.
      const httpOptions = $scope.callHeaders(userName, userPassword, authType);
      let callURI =
        piWebAPIUrl +
        '/attributes?path=\\\\' +
        assetServer +
        '\\' +
        $scope.databaseName +
        '\\' +
        $scope.elementName +
        '|' +
        $scope.sampleTagAttributeName;

      // Write the URI we're about to call to the textarea in the UI.
      $scope.callURIText =
        'GET Request URI to retrieve the ' +
        $scope.sampleTagAttributeName +
        ': ' +
        callURI;

      // Get the sample tag.
      return $scope
        .makeGETRequest(callURI, httpOptions, authType)
        .then(function (result) {
          // Build the next URI for the POST request.
          callURI =
            piWebAPIUrl +
            '/streams/' +
            result[$scope.resultBody][$scope.resultWebId] +
            '/recorded?startTime=*-2d';

          // Write the URI we're about to call to the textarea in the UI.
          $scope.callURIText +=
            '\nGET Request URI to retrieve the recorded values: ' + callURI;

          // Make a get request to retrieve the recorded values.
          return $scope.makeGETRequest(callURI, httpOptions, authType);
        })
        .then(function (result) {
          $scope.returnCode = result[$scope.returnStatus];
          $scope.codeResult =
            $scope.sampleTagAttributeName +
            ' Values: ' +
            JSON.stringify(result, null, 2);
          return $scope.returnCode;
        })
        .catch(function (response) {
          $scope.returnCode = response.status;
          $scope.codeResult = 'An error occurred. ' + response.statusText;
          return $scope.returnCode;
        });
    } catch (e) {
      console.log(e);
      $scope.codeResult = e.message;
    }
  };

  /**
   * Read sampleTag values with selected fields to reduce payload size.
   * @param {string} piWebAPIUrl Location of the PI Web API instance.
   * @param {string} assetServer Name of the PI Web API Asset Server (AF).
   * @param {string} userName The user's credentials name.
   * @param {string} userPassword The user's credentials password.
   * @param {string} authType The authentication type (basic or kerberos).
   * @return {number} The return code of the last PI Web API request.
   */
  $scope.reducePayloadWithSelectedFields = function (
    piWebAPIUrl,
    assetServer,
    userName,
    userPassword,
    authType
  ) {
    try {
      // Create the header and URI for the GET request.
      const httpOptions = $scope.callHeaders(userName, userPassword, authType);
      let callURI =
        piWebAPIUrl +
        '/attributes?path=\\\\' +
        assetServer +
        '\\' +
        $scope.databaseName +
        '\\' +
        $scope.elementName +
        '|' +
        $scope.sampleTagAttributeName;

      // Write the URI we're about to call to the textarea in the UI.
      $scope.callURIText =
        'GET Request URI to retrieve the ' +
        $scope.sampleTagAttributeName +
        ': ' +
        callURI;

      // Get the sample tag.
      return $scope
        .makeGETRequest(callURI, httpOptions, authType)
        .then(function (result) {
          // Build the next URI for the POST request.
          callURI =
            piWebAPIUrl +
            '/streams/' +
            result[$scope.resultBody][$scope.resultWebId] +
            '/recorded?startTime=*-2d&selectedFields=Items.Timestamp;Items.Value';

          // Write the URI we're about to call to the textarea in the UI.
          $scope.callURIText +=
            '\nGET Request URI to retrieve the recorded values selected fields: ' +
            callURI;

          // Make a get request to retrieve the recorded values - restrict the response to only
          //  include the TimeStamp and Value fields.
          return $scope.makeGETRequest(callURI, httpOptions, authType);
        })
        .then(function (result) {
          $scope.returnCode = result[$scope.returnStatus];
          $scope.codeResult =
            $scope.sampleTagAttributeName +
            ' Values with Selected Fields: ' +
            JSON.stringify(result, null, 2);
          return $scope.returnCode;
        })
        .catch(function (response) {
          $scope.returnCode = response.status;
          $scope.codeResult = 'An error occurred. ' + response.statusText;
          return $scope.returnCode;
        });
    } catch (e) {
      console.log(e);
      $scope.codeResult = e.message;
    }
  };

  /**
   * Read sampleTag values with selected fields to reduce payload size.
   * @param {string} piWebAPIUrl Location of the PI Web API instance.
   * @param {string} assetServer Name of the PI Web API Asset Server (AF).
   * @param {string} userName The user's credentials name.
   * @param {string} userPassword The user's credentials password.
   * @param {string} authType The authentication type (basic or kerberos).
   * @return {number} The return code of the last PI Web API request.
   */
  $scope.doBatchCall = function (
    piWebAPIUrl,
    assetServer,
    userName,
    userPassword,
    authType
  ) {
    try {
      // Create the header and URI for the GET request.
      const httpOptions = $scope.callHeaders(userName, userPassword, authType);
      let callURI =
        piWebAPIUrl +
        '/attributes?path=\\\\' +
        assetServer +
        '\\' +
        $scope.databaseName +
        '\\' +
        $scope.elementName +
        '|' +
        $scope.sampleTagAttributeName;

      // Write the URI we're about to call to the textarea in the UI.
      $scope.callURIText =
        'GET Request URI to retrieve the SampleTag: ' + callURI;

      // Get the sample tag.
      return $scope
        .makeGETRequest(callURI, httpOptions, authType)
        .then(function (result) {
          const attributeValue = (Math.random() * 10).toFixed(4);

          // Construct the batch request's message body.
          // 1:  Get the sample tag.
          // 2:  Get the sample tag's snapshot value.
          // 3:  Get the sample tag's last 10 recorded values.
          // 4:  Write a snapshot value to the sample tag.
          // 5:  Write a set of recorded values to the sample tag.
          // 6:  Get the sample tag's last 10 recorded values, only returning the value and timestamp.
          const batchRequest = {
            1: {
              Method: 'GET',
              Resource:
                piWebAPIUrl +
                '/attributes?path=\\\\' +
                assetServer +
                '\\' +
                $scope.databaseName +
                '\\' +
                $scope.elementName +
                '|' +
                $scope.sampleTagAttributeName,
              Content: '{}',
            },
            2: {
              Method: 'GET',
              Resource: piWebAPIUrl + '/streams/{0}/value',
              Content: '{}',
              Parameters: ['$.1.Content.WebId'],
              ParentIds: ['1'],
            },
            3: {
              Method: 'GET',
              Resource: piWebAPIUrl + '/streams/{0}/recorded?maxCount=10',
              Content: '{}',
              Parameters: ['$.1.Content.WebId'],
              ParentIds: ['1'],
            },
            4: {
              Method: 'PUT',
              Resource: piWebAPIUrl + '/attributes/{0}/value',
              Content: "{'Value':" + attributeValue + '}',
              Parameters: ['$.1.Content.WebId'],
              ParentIds: ['1'],
            },
            5: {
              Method: 'POST',
              Resource: piWebAPIUrl + '/streams/{0}/recorded',
              Content: "[{'Value': '111'}, {'Value': '222'}, {'Value': '333'}]",
              Parameters: ['$.1.Content.WebId'],
              ParentIds: ['1'],
            },
            6: {
              Method: 'GET',
              Resource:
                piWebAPIUrl +
                '/streams/{0}/recorded?maxCount=10&selectedFields=Items.Timestamp;Items.Value',
              Content: '{}',
              Parameters: ['$.1.Content.WebId'],
              ParentIds: ['1'],
            },
          };

          // Build the next URI for the POST request.
          callURI = piWebAPIUrl + '/batch';

          // Write the URI we're about to call to the textarea in the UI.
          $scope.callURIText +=
            '\nPOST Request URI to execute the batch: ' + callURI;
          $scope.callURIText +=
            '\n\nPOST request body:\n' + JSON.stringify(batchRequest, null, 2);

          // Make a get request to retrieve the recorded values - restrict the response to only.
          // include the TimeStamp and Value fields.
          return $scope.makePOSTRequest(
            callURI,
            httpOptions,
            batchRequest,
            authType
          );
        })
        .then(function (result) {
          $scope.returnCode = result[$scope.returnStatus];
          $scope.codeResult = JSON.stringify(result, null, 2);
          return $scope.returnCode;
        })
        .catch(function (response) {
          $scope.returnCode = response.status;
          $scope.codeResult = 'An error occurred. ' + response.statusText;
          return $scope.returnCode;
        });
    } catch (e) {
      console.log(e);
      $scope.codeResult = e.message;
    }
  };

  /**
   * Delete an AF Element.
   * @param {string} piWebAPIUrl Location of the PI Web API instance.
   * @param {string} assetServer Name of the PI Web API Asset Server (AF).
   * @param {string} userName The user's credentials name.
   * @param {string} userPassword The user's credentials password.
   * @param {string} authType The authentication type (basic or kerberos).
   * @return {number} The return code of the last PI Web API request.
   */
  $scope.deleteElement = function (
    piWebAPIUrl,
    assetServer,
    userName,
    userPassword,
    authType
  ) {
    try {
      // Create the header and URI for the GET request.
      const httpOptions = $scope.callHeaders(userName, userPassword, authType);
      let callURI =
        piWebAPIUrl +
        '/elements?path=\\\\' +
        assetServer +
        '\\' +
        $scope.databaseName +
        '\\' +
        $scope.elementName;

      // Write the URI we're about to call to the textarea in the UI.
      $scope.callURIText =
        'GET Request URI to retrieve the AF element: ' + callURI;

      // Get the AF element.
      return $scope
        .makeGETRequest(callURI, httpOptions, authType)
        .then(function (result) {
          // Build the next URI for the DELETE request.
          callURI =
            result[$scope.resultBody][$scope.resultLinks][$scope.resultSelf];

          // Write the URI we're about to call to the textarea in the UI.
          $scope.callURIText +=
            '\nDELETE Request URI to delete the AF element: ' + callURI;

          // Make a delete request to delete the category.
          return $scope.makeDELETERequest(callURI, httpOptions, authType);
        })
        .then(function (result) {
          $scope.returnCode = result[$scope.returnStatus];
          $scope.codeResult = 'Element ' + $scope.elementName + ' Deleted';
          return $scope.returnCode;
        })
        .catch(function (response) {
          $scope.returnCode = response.status;
          $scope.codeResult = 'An error occurred. ' + response.statusText;
          return $scope.returnCode;
        });
    } catch (e) {
      $scope.codeResult = e.message;
    }
  };

  /**
   * Delete an AF Template.
   * @param {string} piWebAPIUrl Location of the PI Web API instance.
   * @param {string} assetServer Name of the PI Web API Asset Server (AF).
   * @param {string} userName The user's credentials name.
   * @param {string} userPassword The user's credentials password.
   * @param {string} authType The authentication type (basic or kerberos).
   * @return {number} The return code of the last PI Web API request.
   */
  $scope.deleteTemplate = function (
    piWebAPIUrl,
    assetServer,
    userName,
    userPassword,
    authType
  ) {
    try {
      // Create the header and URI for the GET request.
      const httpOptions = $scope.callHeaders(userName, userPassword, authType);
      let callURI =
        piWebAPIUrl +
        '/elementtemplates?path=\\\\' +
        assetServer +
        '\\' +
        $scope.databaseName +
        '\\ElementTemplates[' +
        $scope.templateName +
        ']';

      // Write the URI we're about to call to the textarea in the UI.
      $scope.callURIText =
        'GET Request URI to retrieve the AF template: ' + callURI;

      // Get the AF template.
      return $scope
        .makeGETRequest(callURI, httpOptions, authType)
        .then(function (result) {
          // Build the next URI for the DELETE request.
          callURI =
            piWebAPIUrl +
            '/elementtemplates/' +
            result[$scope.resultBody][$scope.resultWebId];

          // Write the URI we're about to call to the textarea in the UI.
          $scope.callURIText +=
            '\nDELETE Request URI to delete the AF template: ' + callURI;

          // Make a delete request to delete the category.
          return $scope.makeDELETERequest(callURI, httpOptions, authType);
        })
        .then(function (result) {
          $scope.returnCode = result[$scope.returnStatus];
          $scope.codeResult = 'Template ' + $scope.templateName + ' deleted';
          return $scope.returnCode;
        })
        .catch(function (response) {
          $scope.returnCode = response.status;
          $scope.codeResult = 'An error occurred. ' + response.statusText;
          return $scope.returnCode;
        });
    } catch (e) {
      $scope.codeResult = e.message;
    }
  };

  /**
   * Delete an AF Category.
   * @param {string} piWebAPIUrl Location of the PI Web API instance.
   * @param {string} assetServer Name of the PI Web API Asset Server (AF).
   * @param {string} userName The user's credentials name.
   * @param {string} userPassword The user's credentials password.
   * @param {string} authType The authentication type (basic or kerberos).
   * @return {number} The return code of the last PI Web API request.
   */
  $scope.deleteCategory = function (
    piWebAPIUrl,
    assetServer,
    userName,
    userPassword,
    authType
  ) {
    try {
      // Create the header and URI for the GET request.
      const httpOptions = $scope.callHeaders(userName, userPassword, authType);
      let callURI =
        piWebAPIUrl +
        '/elementcategories?path=\\\\' +
        assetServer +
        '\\' +
        $scope.databaseName +
        '\\CategoriesElement[' +
        $scope.categoryName +
        ']';

      // Write the URI we're about to call to the textarea in the UI.
      $scope.callURIText =
        'GET Request URI to retrieve the AF category: ' + callURI;

      // Get the AF category.
      return $scope
        .makeGETRequest(callURI, httpOptions, authType)
        .then(function (result) {
          // Build the next URI for the DELETE request.
          callURI =
            result[$scope.resultBody][$scope.resultLinks][$scope.resultSelf];

          // Write the URI we're about to call to the textarea in the UI.
          $scope.callURIText +=
            '\nDELETE Request URI to delete the AF category: ' + callURI;

          // Make a delete request to delete the category.
          return $scope.makeDELETERequest(callURI, httpOptions, authType);
        })
        .then(function (result) {
          $scope.returnCode = result[$scope.returnStatus];
          $scope.codeResult = 'Category ' + $scope.categoryName + ' deleted';
          return $scope.returnCode;
        })
        .catch(function (response) {
          $scope.returnCode = response.status;
          $scope.codeResult = 'An error occurred. ' + response.statusText;
          return $scope.returnCode;
        });
    } catch (e) {
      $scope.codeResult = e.message;
    }
  };

  /**
   * Delete the AngularJS Web API Sample database.
   * @param {string} piWebAPIUrl Location of the PI Web API instance.
   * @param {string} assetServer Name of the PI Web API Asset Server (AF).
   * @param {string} userName The user's credentials name.
   * @param {string} userPassword The user's credentials password.
   * @param {string} authType The authentication type (basic or kerberos).
   * @return {number} The return code of the last PI Web API request.
   */
  $scope.deleteDatabase = function (
    piWebAPIUrl,
    assetServer,
    userName,
    userPassword,
    authType
  ) {
    try {
      // Create the header and URI for the GET request.
      const httpOptions = $scope.callHeaders(userName, userPassword, authType);
      let callURI =
        piWebAPIUrl +
        '/assetdatabases?path=\\\\' +
        assetServer +
        '\\' +
        $scope.databaseName;

      // Write the URI we're about to call to the textarea in the UI.
      $scope.callURIText =
        'GET request URI to retrieve the database: ' + callURI;

      // Get the database.
      return $scope
        .makeGETRequest(callURI, httpOptions, authType)
        .then(function (result) {
          // Build the next URI for the DELETE request.
          callURI =
            piWebAPIUrl +
            '/assetdatabases/' +
            result[$scope.resultBody][$scope.resultWebId];

          // Write the URI we're about to call to the textarea in the UI.
          $scope.callURIText +=
            '\nDELETE request URI to delete the database: ' + callURI;

          // Make a delete request to delete the database.
          return $scope.makeDELETERequest(callURI, httpOptions, authType);
        })
        .then(function (result) {
          $scope.returnCode = result[$scope.returnStatus];
          $scope.codeResult = 'Database ' + $scope.databaseName + ' deleted';
          return $scope.returnCode;
        })
        .catch(function (response) {
          $scope.returnCode = response.status;
          $scope.codeResult = 'An error occurred. ' + response.statusText;
          return $scope.returnCode;
        });
    } catch (e) {
      $scope.codeResult = e.message;
    }
  };

  /**
   * Make a GET request.
   * @param {string} callURI PI Web API URI for the call.
   * @param {string} httpOptions HTTP Header and authorization information.
   * @param {string} authType Authorization type:  basic or kerberos.
   * @return {Promise} The promise created by the http request.
   */
  $scope.makeGETRequest = function (callURI, httpOptions, authType) {
    return $http({
      method: 'GET',
      url: callURI,
      headers: httpOptions,
      withCredentials: authType === 'kerberos',
    });
  };

  /**
   * Make a GET request.
   * @param {string} callURI PI Web API URI for the call.
   * @param {string} httpOptions HTTP Header and authorization information.
   * @param {string} requestBody JSON request body.
   * @param {string} authType Authorization type:  basic or kerberos.
   * @return {Promise} The promise created by the http request.
   */
  $scope.makePOSTRequest = function (
    callURI,
    httpOptions,
    requestBody,
    authType
  ) {
    return $http({
      method: 'POST',
      url: callURI,
      headers: httpOptions,
      data: requestBody,
      withCredentials: authType === 'kerberos',
    });
  };

  /**
   * Make a DELETE request with the HTTPClient.
   * @param {string} callURI PI Web API URI for the call.
   * @param {string} httpOptions  HTTP Header and authorization information.
   * @param {string} authType  Authorization type:  basic or kerberos.
   * @return {Promise} The promise created by the http request.
   */
  $scope.makeDELETERequest = function (callURI, httpOptions, authType) {
    return $http({
      method: 'DELETE',
      url: callURI,
      headers: httpOptions,
      withCredentials: authType === 'kerberos',
    });
  };

  /**
   * Make a PUT request with the HTTPClient.
   * @param {string} callURI PI Web API URI for the call.
   * @param {string} httpOptions HTTP Header and authorization information.
   * @param {string} requestBody JSON request body.$.
   * @param {string} authType Authorization type:  basic or kerberos.
   * @return {Promise} The promise created by the http request.
   */
  $scope.makePUTRequest = function (
    callURI,
    httpOptions,
    requestBody,
    authType
  ) {
    return $http({
      method: 'PUT',
      url: callURI,
      headers: httpOptions,
      data: requestBody,
      withCredentials: authType === 'kerberos',
    });
  };

  $scope.onButtonClick = function () {
    let returnCode = 0;

    switch ($scope.selectedCallOption) {
      case 'createDatabase': {
        returnCode = $scope.createDatabase(
          $scope.piWebAPIUrl,
          $scope.assetServer,
          $scope.userName,
          $scope.userPassword,
          $scope.securityMethod
        );
        returnCode.then(function (result) {
          console.log(result);
          console.log(returnCode);
        });

        break;
      }
      case 'createcategory': {
        $scope.createCategory(
          $scope.piWebAPIUrl,
          $scope.assetServer,
          $scope.userName,
          $scope.userPassword,
          $scope.securityMethod
        );
        break;
      }
      case 'createtemplate': {
        $scope.createTemplate(
          $scope.piWebAPIUrl,
          $scope.assetServer,
          $scope.piServerName,
          $scope.userName,
          $scope.userPassword,
          $scope.securityMethod
        );
        break;
      }
      case 'createelement': {
        $scope.createElement(
          $scope.piWebAPIUrl,
          $scope.assetServer,
          $scope.userName,
          $scope.userPassword,
          $scope.securityMethod
        );
        break;
      }
      case 'deleteelement': {
        $scope.deleteElement(
          $scope.piWebAPIUrl,
          $scope.assetServer,
          $scope.userName,
          $scope.userPassword,
          $scope.securityMethod
        );
        break;
      }
      case 'deletetemplate': {
        $scope.deleteTemplate(
          $scope.piWebAPIUrl,
          $scope.assetServer,
          $scope.userName,
          $scope.userPassword,
          $scope.securityMethod
        );
        break;
      }
      case 'deletecategory': {
        $scope.deleteCategory(
          $scope.piWebAPIUrl,
          $scope.assetServer,
          $scope.userName,
          $scope.userPassword,
          $scope.securityMethod
        );
        break;
      }
      case 'deletedatabase': {
        $scope.deleteDatabase(
          $scope.piWebAPIUrl,
          $scope.assetServer,
          $scope.userName,
          $scope.userPassword,
          $scope.securityMethod
        );
        break;
      }
      case 'writesinglevalue': {
        $scope.writeSingleValue(
          $scope.piWebAPIUrl,
          $scope.assetServer,
          $scope.userName,
          $scope.userPassword,
          $scope.securityMethod
        );
        break;
      }
      case 'writerecordedvalues': {
        $scope.writeSetOfValues(
          $scope.piWebAPIUrl,
          $scope.assetServer,
          $scope.userName,
          $scope.userPassword,
          $scope.securityMethod
        );
        break;
      }
      case 'getsnapshotvalue': {
        $scope.readSingleValue(
          $scope.piWebAPIUrl,
          $scope.assetServer,
          $scope.userName,
          $scope.userPassword,
          $scope.securityMethod
        );
        break;
      }
      case 'getrecordedvalues': {
        $scope.readSetOfValues(
          $scope.piWebAPIUrl,
          $scope.assetServer,
          $scope.userName,
          $scope.userPassword,
          $scope.securityMethod
        );
        break;
      }
      case 'payloadselectedfields': {
        $scope.reducePayloadWithSelectedFields(
          $scope.piWebAPIUrl,
          $scope.assetServer,
          $scope.userName,
          $scope.userPassword,
          $scope.securityMethod
        );
        break;
      }
      case 'batch': {
        $scope.doBatchCall(
          $scope.piWebAPIUrl,
          $scope.assetServer,
          $scope.userName,
          $scope.userPassword,
          $scope.securityMethod
        );
        break;
      }
      case 'updatevalue': {
        $scope.updateAttributeValue(
          $scope.piWebAPIUrl,
          $scope.assetServer,
          $scope.userName,
          $scope.userPassword,
          $scope.securityMethod
        );
        break;
      }

      default: {
        break;
      }
    }
  };
});
