import { Injectable } from '@angular/core';
import { HttpClient, HttpHeaders } from '@angular/common/http';
import { APIResponse } from '../models/piwebapi.model';
import { switchMap, map, catchError } from 'rxjs/operators';
import { Observable, of, forkJoin } from 'rxjs';

@Injectable({
  providedIn: 'root'
})
export class PIWebAPIService {
    constructor(private httpClient: HttpClient) { }

    //  define string constants for the results we're interested in to prevent lint errors
    resultBody = 'body';
    resultLinks = 'Links';
    resultValue = 'Value';
    resultSelf = 'Self';
    resultWebId = 'WebId';
    returnStatus = 'status';

    //  define string constants for the AF objects created for the sandbox
    databaseName = 'OSIAngularDatabase';
    categoryName = 'OSIAngularCategory';
    templateName = 'OSIAngularTemplate';
    elementName = 'OSIAngularElement';
    activeAttributeName = 'OSIAngularAttributeActive';
    sinusoidUAttributeName = 'OSIAngularAttributeSinusoidU';
    sinusoidAttributeName = 'OSIAngularAttributeSinusoid';
    sampleTagName = 'OSIAngularSampleTag';
    sampleTagAttributeName = 'OSIAngularAttributeSampleTag';

    //  create an object to use for returing the observables
    apiResponse = { callURIText: '',
                    codeResult: '',
                    returnCode: 0 };

    /**
     * Create sample data used by subsequent calls
     */
    createTestData() {
        const dteTestData = [];
        const fiveMinutes = 5 * 60 * 1000;
        const dte = new Date(new Date().setHours(0, 0, 0, 0));
        dte.setDate(dte.getDate() - 2);
        for (let i = 1; i <= 100; i++) {
            dte.setTime(dte.getTime() - fiveMinutes);
            const testItem = {Value: (Math.random() * 10).toFixed(4), Timestamp: dte.toUTCString()};
            dteTestData.push(testItem);
        }
        return dteTestData;
    }

    /**
     * Create API call headers based on authorization type
     * @param userName string: The user's credentials name
     * @param userPassword string: The user's credentials password
     * @param authType string: Authorization type:  basic or kerberos
     * @param includeContentType bool:  flag determines whether or not the Content-Type header is included
     */
    callHeaders(userName: string, userPassword: string, authType: string,
                includeContentType: boolean) {
        let callHeaders;

        //  For API calls that write or delete, we need to include the Content-Type for basic authentication
        if (includeContentType === true) {
            if (authType === 'kerberos') {
                //  build a kerberos authentication header and include withCredentials
                callHeaders = {
                    headers: new HttpHeaders({
                        'X-Requested-With': 'XmlHttpRequest'
                    })
                    , withCredentials: true
                    , observe: 'response'
                };
            } else {
                //  build a basic authentication header and include the content-type
                callHeaders = {
                    headers: new HttpHeaders({
                        'X-Requested-With': 'XmlHttpRequest',
                        'Content-Type': 'application/json',
                        Authorization: 'Basic ' + btoa(userName + ':' + userPassword)
                    })
                    , observe: 'response'
                };
            }
        } else {
            //  For API calls that read, we do not need to include Content-Type
            if (authType === 'kerberos') {
                //  build a kerberos authentication header and include withCredentials
                callHeaders = {
                    headers: new HttpHeaders({
                        'X-Requested-With': 'XmlHttpRequest'
                    })
                    , withCredentials: true
                    , observe: 'response'
                };
            } else {
                //  build a basic authentication header - no need for the content-type
                callHeaders = {
                    headers: new HttpHeaders({
                        'X-Requested-With': 'XmlHttpRequest',
                        Authorization: 'Basic ' + btoa(userName + ':' + userPassword)
                    })
                    , observe: 'response'
                };
            }
        }
        return callHeaders;
    }

    /**
     * Create a sample Web API database
     * @param piWebAPIUrl string: Location of the PI Web API instance
     * @param assetServer  string:  Name of the PI Web API Asset Server (AF)
     * @param userName string:  The user's credentials name
     * @param userPassword  string:  The user's credentials password
     * @param authType string:  The authentication type (basic or kerberos)
     */
    createDatabase(piWebAPIUrl: string, assetServer: string, userName: string,
                   userPassword: string, authType: string): Observable<APIResponse> {
        try {
            //  Create the header for the GET request
            let httpOptions = this.callHeaders(userName, userPassword, authType, false);
            let callURI: string = piWebAPIUrl + '/assetservers?path=\\\\' + assetServer;

            //  Write the URI we're about to call to the textarea in the UI
            this.apiResponse.callURIText = 'GET request URI to retrieve the Asset Server: ' + callURI;

            //  Get the asset server
            return this.makeGetRequest(callURI, httpOptions)
            .pipe(
                switchMap((result) => {
                    //  construct the request body
                    const requestBody = {
                        Name: this.databaseName,
                        Description: 'Database for OSI Angular Web API Sample',
                        ExtendedProperties: {}
                    };

                    //  Create the header for the POST request
                    httpOptions = this.callHeaders(userName, userPassword, authType, true);

                    callURI = result[this.resultBody][this.resultLinks][this.resultSelf] + '/assetdatabases';

                    //  Write the URI we're about to call to the textarea in the UI
                    this.apiResponse.callURIText += '\nPOST request URI to create the database: ' + callURI;
                    this.apiResponse.callURIText += '\n\nPOST request body:\n' + JSON.stringify(requestBody, null, 2);

                    return this.makePostRequest(callURI, requestBody, httpOptions);
                }),
                map((response) => {
                    this.apiResponse.codeResult = 'Database ' + this.databaseName + ' created';
                    this.apiResponse.returnCode = response[this.returnStatus];
                    return this.apiResponse;
                }),
                catchError((error) => {
                    this.apiResponse.codeResult = 'An error occured:  ' + error.message;
                    return of(this.apiResponse);
                })
            );
        } catch (e) {
            this.apiResponse.codeResult = e.message;
            return of(this.apiResponse);
        }
    }

    /**
     * Create an AF Category
     * @param piWebAPIUrl string: Location of the PI Web API instance
     * @param assetServer  string:  Name of the PI Web API Asset Server (AF)
     * @param userName string:  The user's credentials name
     * @param userPassword  string:  The user's credentials password
     * @param authType string:  The authentication type (basic or kerberos)
     */
    createCategory(piWebAPIUrl: string, assetServer: string, userName: string,
                   userPassword: string, authType: string): Observable<APIResponse> {
        try {
            //  Create the header for the GET request
            let httpOptions = this.callHeaders(userName, userPassword, authType, false);
            let callURI: string = piWebAPIUrl + '/assetdatabases?path=\\\\' + assetServer + '\\' + this.databaseName;

            //  Write the URI we're about to call to the textarea in the UI
            this.apiResponse.callURIText = 'GET Request URI to retrieve the database: ' + callURI;

            //  Get the asset server database
            return this.makeGetRequest(callURI, httpOptions)
            .pipe(
                switchMap((result) => {
                    //  Create the requestbody for the POST request
                    const requestBody = {
                        Name: this.categoryName,
                        Description: 'Sample ' + this.templateName + ' category'
                    };

                    //  Create the header for the POST request
                    httpOptions = this.callHeaders(userName, userPassword, authType, true);
                    callURI = result[this.resultBody][this.resultLinks][this.resultSelf] + '/elementcategories';

                    //  Write the URI we're about to call to the textarea in the UI
                    this.apiResponse.callURIText += '\nPOST Request URI to create the category: ' + callURI;
                    this.apiResponse.callURIText += '\n\nPOST request body:\n' + JSON.stringify(requestBody, null, 2);

                    //  Make a post request to create the category
                    return this.makePostRequest(callURI, requestBody, httpOptions);
                }),
                map((response) => {
                    this.apiResponse.codeResult = 'Category ' + this.categoryName + ' created';
                    this.apiResponse.returnCode = response[this.returnStatus];
                    return this.apiResponse;
                }),
                catchError((error) => {
                    this.apiResponse.codeResult = 'An error occured:  ' + error.message;
                    return of(this.apiResponse);
                })
            );
        } catch (e) {
            this.apiResponse.codeResult = e.message;
            return of(this.apiResponse);
        }
    }

    /**
     * Create an AF Template
     * @param piWebAPIUrl string: Location of the PI Web API instance
     * @param assetServer  string:  Name of the PI Web API Asset Server (AF)
     * @param userName string:  The user's credentials name
     * @param userPassword  string:  The user's credentials password
     * @param authType string:  The authentication type (basic or kerberos)
     */
    createTemplate(piWebAPIUrl: string, assetServer: string, piServer: string, userName: string,
                   userPassword: string, authType: string): Observable<APIResponse>  {
        try {
            //  Create the header for the GET request
            let httpOptions = this.callHeaders(userName, userPassword, authType, false);
            let callURI: string = piWebAPIUrl + '/assetdatabases?path=\\\\' + assetServer + '\\' + this.databaseName;

            //  Write the URI we're about to call to the textarea in the UI
            this.apiResponse.callURIText = 'GET Request URI to retrieve the database: ' + callURI;

            //  Get the asset server database
            return this.makeGetRequest(callURI, httpOptions)
            .pipe(
                switchMap((result) => {
                    //  Create the requestbody for the POST request
                    const requestBody = {
                        Name: this.templateName,
                        Description: 'Sample ' + this.templateName + ' Template',
                        CategoryNames: [this.categoryName],
                        AllowElementToExtend: true
                    };

                    //  Create the header for the POST request
                    httpOptions = this.callHeaders(userName, userPassword, authType, true);
                    callURI = result[this.resultBody][this.resultLinks][this.resultSelf] + '/elementtemplates';

                    //  Write the URI we're about to call to the textarea in the UI
                    this.apiResponse.callURIText += '\nPOST Request URI to create the template: ' + callURI;
                    this.apiResponse.callURIText += '\n\nPOST request body:\n' + JSON.stringify(requestBody, null, 2);

                    //  Make a post request to create the AF template
                    return this.makePostRequest(callURI, requestBody, httpOptions);
                }),
                switchMap((response) => {
                    this.apiResponse.codeResult = 'Element Template created';

                    //  Write the URI we're about to call to the textarea in the UI
                    callURI = piWebAPIUrl + '/elementtemplates?path=\\\\' + assetServer + '\\' + this.databaseName +
                              '\\ElementTemplates[' + this.templateName + ']';
                    this.apiResponse.callURIText += '\n\nGET Request URI to retrieve the newly created template: ' + callURI;
                    //  Get the newly created template
                    return this.makeGetRequest(callURI, httpOptions);
                }),
                switchMap((template) => {
                    callURI = template[this.resultBody][this.resultLinks][this.resultSelf] + '/attributetemplates';
                    //  Write the URI we're about to call to the textarea in the UI
                    this.apiResponse.callURIText += '\nPOST Request URI to create an attribute: ' + callURI;
                    this.apiResponse.callURIText += '\n\nPOST ' + this.activeAttributeName + ' attribute request body:\n' + JSON.stringify({
                        Name: this.activeAttributeName, Description: '',
                        IsConfigurationItem: true, Type: 'Boolean'
                    }, null, 2);
                    //  Add template attribute
                    const makeActiveAttr$ = this.makePostRequest(callURI, {
                        Name: this.activeAttributeName, Description: '', IsConfigurationItem: true,
                        Type: 'Boolean'
                    }, httpOptions);
                    this.apiResponse.codeResult += '\n' + this.activeAttributeName + ' attribute template created';
                    //  Write the URI we're about to call to the textarea in the UI
                    this.apiResponse.callURIText += '\n\nPOST OS attribute request body:\n' + JSON.stringify({
                        Name: 'OS', Description: 'Operating System',
                        IsConfigurationItem: true, Type: 'String'
                    }, null, 2);
                    //  Add template attribute:  OS
                    const makeOSAttr$ = this.makePostRequest(callURI, {
                        Name: 'OS', Description: 'Operating System', IsConfigurationItem: true,
                        Type: 'String'
                    }, httpOptions);

                    this.apiResponse.codeResult += '\nOS attribute template created';
                    //  Write the URI we're about to call to the textarea in the UI
                    this.apiResponse.callURIText += '\n\nPOST OSVersion attribute request body:\n' + JSON.stringify({
                        Name: 'OSVersion',
                        Description: 'Operating System Version', IsConfigurationItem: true, Type: 'String'
                    }, null, 2);
                    //  Add template attribute:  OSVersion
                    const makeOSVersionAttr$ = this.makePostRequest(callURI, {
                        Name: 'OSVersion', Description: 'Operating System Version',
                        IsConfigurationItem: true, Type: 'String'
                    }, httpOptions);

                    this.apiResponse.codeResult += '\nOSVersion attribute template created';
                    //  Write the URI we're about to call to the textarea in the UI
                    this.apiResponse.callURIText += '\n\nPOST IPAddress attribute request body:\n' + JSON.stringify({
                        Name: 'IPAddresses',
                        Description: 'A list of IP Addresses for all NIC in the machine', IsConfigurationItem: true, Type: 'String'
                    }, null, 2);
                    //  Add template attribute:  IPAddresses
                    const makeIPAddressAttr$ = this.makePostRequest(callURI, {
                        Name: 'IPAddresses', Description:
                            'A list of IP Addresses for all NIC in the machine', IsConfigurationItem: true, Type: 'String'
                    }, httpOptions);

                    this.apiResponse.codeResult += '\nIPAddresses attribute template created';

                    //  Write the URI we're about to call to the textarea in the UI
                    this.apiResponse.callURIText += '\n\nPOST ' + this.sinusoidUAttributeName + ' attribute request body:\n' +
                        JSON.stringify({ Name: this.sinusoidUAttributeName, Description: '',
                        IsConfigurationItem: false, Type: 'Double', DataReferencePlugIn: 'PI Point',
                        ConfigString: '\\\\' + piServer + '\\SinusoidU'
                    } , null, 2);
                    //  Add Sinusoid U
                    const makeSinusoidUAttr$ = this.makePostRequest(callURI, {
                        Name: this.sinusoidUAttributeName, Description: '', IsConfigurationItem: false, Type: 'Double',
                        DataReferencePlugIn: 'PI Point', ConfigString: '\\\\' + piServer + '\\SinusoidU'
                    }, httpOptions);

                    this.apiResponse.codeResult += '\n' + this.sinusoidUAttributeName + ' attribute template created';

                    //  Write the URI we're about to call to the textarea in the UI
                    this.apiResponse.callURIText += '\n\nPOST ' + this.sinusoidAttributeName + ' attribute request body:\n' +
                        JSON.stringify({Name: this.sinusoidAttributeName, Description: '', IsConfigurationItem: false, Type: 'Double',
                        DataReferencePlugIn: 'PI Point', ConfigString: '\\\\' + piServer + '\\Sinusoid'
                    }, null, 2);
                    //  Add Sinusoid
                    const makeSinusoidAttr$ = this.makePostRequest(callURI, {
                        Name: this.sinusoidAttributeName, Description: '', IsConfigurationItem: false, Type: 'Double',
                        DataReferencePlugIn: 'PI Point', ConfigString: '\\\\' + piServer + '\\Sinusoid'
                    }, httpOptions);

                    this.apiResponse.codeResult += '\n' + this.sinusoidAttributeName + ' attribute template created';

                    //  Write the URI we're about to call to the textarea in the UI
                    this.apiResponse.callURIText += '\n\nPOST ' + this.sampleTagAttributeName + ' request body:\n' + JSON.stringify({
                        Name: this.sampleTagAttributeName, Description: '',
                        IsConfigurationItem: false, Type: 'Double', DataReferencePlugIn: 'PI Point', ConfigString: '\\\\' + piServer +
                            '\\%Element%_' + this.sampleTagName +
                            ';ReadOnly=False;ptclassname=classic;pointtype=Float64;pointsource=webapi'
                    }, null, 2);
                    //  Add the sampleTag attribute
                    const makeSampleTagAttr$ = this.makePostRequest(callURI, {
                        Name: this.sampleTagAttributeName, Description: '', IsConfigurationItem: false, Type: 'Double',
                        DataReferencePlugIn: 'PI Point', ConfigString: '\\\\' + piServer + '\\%Element%_' + this.sampleTagName +
                        ';ReadOnly=False;ptclassname=classic;pointtype=Float64;pointsource=webapi'
                    }, httpOptions);

                    //  wait for all the observables to complete and then emit the last emitted value of each observable
                    return forkJoin([makeActiveAttr$, makeIPAddressAttr$, makeOSAttr$, makeOSVersionAttr$, makeSampleTagAttr$,
                                    makeSinusoidUAttr$, makeSinusoidAttr$]);
                }),
                map((response) => {
                    this.apiResponse.codeResult = '\n' + this.sampleTagAttributeName + ' template created';
                    //  Get the last POST request's status code and return it
                    this.apiResponse.returnCode = response[6][this.returnStatus];
                    return this.apiResponse;
                }),
                catchError((error) => {
                    this.apiResponse.codeResult = 'An error occured:  ' + error.message;
                    return of(this.apiResponse);
                })
            );
        } catch (e) {
            this.apiResponse.codeResult = e.message;
            return of(this.apiResponse);
        }
    }

    /**
     * Create an AF Element
     * @param piWebAPIUrl string: Location of the PI Web API instance
     * @param assetServer  string:  Name of the PI Web API Asset Server (AF)
     * @param userName string:  The user's credentials name
     * @param userPassword  string:  The user's credentials password
     * @param authType string:  The authentication type (basic or kerberos)
     */
    createElement(piWebAPIUrl: string, assetServer: string, userName: string, userPassword: string,
                  authType: string): Observable<APIResponse>  {
        try {
            //  Create the header for the GET request
            let httpOptions = this.callHeaders(userName, userPassword, authType, false);
            let callURI: string = piWebAPIUrl + '/assetdatabases?path=\\\\' + assetServer + '\\' + this.databaseName;

            //  Write the URI we're about to call to the textarea in the UI
            this.apiResponse.callURIText = 'GET Request URI to retrieve the database: ' + callURI;

            //  Get the asset server database
            return this.makeGetRequest(callURI, httpOptions)
            .pipe(
                switchMap((result) => {
                    //  Construct the request body for the POST request
                    const requestBody = {
                        Name: this.elementName,
                        Description: this.elementName + ' element',
                        TemplateName: this.templateName,
                        ExtendedProperties: {}
                    };

                    //  Create the header for the POST request
                    httpOptions = this.callHeaders(userName, userPassword, authType, true);
                    callURI = result[this.resultBody][this.resultLinks][this.resultSelf] + '/elements';

                    //  Write the URI we're about to call to the textarea in the UI
                    this.apiResponse.callURIText += '\nPOST Request URI to create the element: ' + callURI;
                    this.apiResponse.callURIText += '\n\nPOST request body:\n' + JSON.stringify(requestBody, null, 2);

                    //  Make a post request to create the element
                    return this.makePostRequest(callURI, requestBody, httpOptions);
                }),
                switchMap((result) => {
                    this.apiResponse.codeResult = 'Equipment ' + this.elementName + ' created';

                    callURI = piWebAPIUrl + '/elements?path=\\\\' + assetServer + '\\' + this.databaseName + '\\' + this.elementName;
                    //  Write the URI we're about to call to the textarea in the UI
                    this.apiResponse.callURIText += '\n\nGET Request URI to get the newly created element: ' + callURI;

                    //  Get the newly created element
                    return this.makeGetRequest(callURI, httpOptions);
                }),
                switchMap((elementResponse) => {
                    callURI = piWebAPIUrl + '/elements/' + elementResponse[this.resultBody][this.resultWebId] + '/config';
                    //  Write the URI we're about to call to the textarea in the UI
                    this.apiResponse.callURIText += '\nPOST Request URI to create tags based on the template configuration: ' + callURI;
                    this.apiResponse.callURIText += '\n\nPOST request body:\n' + JSON.stringify({ includeChildElements: true }, null, 2);

                    //  Create the tags based on the template configuration
                    return this.makePostRequest(callURI, { includeChildElements: true }, httpOptions);
                }),
                map((tagsResponse) => {
                    this.apiResponse.codeResult = '\nElement tags created';
                    this.apiResponse.returnCode = tagsResponse[this.returnStatus];
                    return this.apiResponse;
                }),
                catchError((error) => {
                    this.apiResponse.codeResult = 'An error occured:  ' + error.message;
                    return of(this.apiResponse);
                })
            );
        } catch (e) {
            this.apiResponse.codeResult = e.message;
            return of(this.apiResponse);
        }
    }

    /**
     * Write a single value to the sampleTag
     * @param piWebAPIUrl string: Location of the PI Web API instance
     * @param assetServer  string:  Name of the PI Web API Asset Server (AF)
     * @param userName string:  The user's credentials name
     * @param userPassword  string:  The user's credentials password
     * @param authType string:  The authentication type (basic or kerberos)
     */
    writeSingleValue(piWebAPIUrl: string, assetServer: string, userName: string, userPassword: string,
                     authType: string): Observable<APIResponse>  {
        try {
            //  Create the header for the GET request
            let httpOptions = this.callHeaders(userName, userPassword, authType, false);
            let callURI: string = piWebAPIUrl + '/attributes?path=\\\\' + assetServer + '\\' + this.databaseName + '\\' +
                                  this.elementName + '|' + this.sampleTagAttributeName;
            let dataValue = 0;

            //  Write the URI we're about to call to the textarea in the UI
            this.apiResponse.callURIText = 'GET Request URI to retrieve the ' + this.sampleTagAttributeName + ': ' + callURI;

            //  Get the sample tag
            return this.makeGetRequest(callURI, httpOptions)
            .pipe(
                switchMap((result) => {
                    //  Create a random number to use are our value and construct a requestbody using that value
                    dataValue = Math.floor(Math.random() * 100) + 1;
                    const requestBody = {
                        Value: dataValue
                    };

                    //  Create the header for the POST request
                    httpOptions = this.callHeaders(userName, userPassword, authType, true);
                    callURI = result[this.resultBody][this.resultLinks][this.resultValue];

                    //  Write the URI we're about to call to the textarea in the UI
                    this.apiResponse.callURIText += '\nPOST Request URI to write the single value: ' + callURI;
                    this.apiResponse.callURIText += '\n\nPOST request body:\n' + JSON.stringify(requestBody, null, 2);

                    //  Make a post request to write the random number to the tag
                    return this.makePostRequest(callURI, requestBody, httpOptions);
                }),
                map((response) => {
                    this.apiResponse.codeResult = 'Attribute ' + this.sampleTagAttributeName + ' write value: ' + dataValue;
                    this.apiResponse.returnCode = response[this.returnStatus];
                    return this.apiResponse;
                }),
                catchError((error) => {
                    this.apiResponse.codeResult = 'An error occured:  ' + error.message;
                    return of(this.apiResponse);
                })
            );
        } catch (e) {
            this.apiResponse.codeResult = e.message;
            return of(this.apiResponse);
        }
    }

    /**
     * Write a set of recorded values to the sampleTag
     * @param piWebAPIUrl string: Location of the PI Web API instance
     * @param assetServer  string:  Name of the PI Web API Asset Server (AF)
     * @param userName string:  The user's credentials name
     * @param userPassword  string:  The user's credentials password
     * @param authType string:  The authentication type (basic or kerberos)
     */
    writeSetOfValues(piWebAPIUrl: string, assetServer: string, userName: string, userPassword: string,
                     authType: string): Observable<APIResponse>  {
        try {
            //  Create the header for the GET request
            let httpOptions = this.callHeaders(userName, userPassword, authType, false);
            let callURI: string = piWebAPIUrl + '/attributes?path=\\\\' + assetServer + '\\' + this.databaseName + '\\' +
                                  this.elementName + '|' + this.sampleTagAttributeName;

            //  Write the URI we're about to call to the textarea in the UI
            this.apiResponse.callURIText = 'GET Request URI to retrieve the ' + this.sampleTagAttributeName + ': ' + callURI;

            //  Get the sample tag
            return this.makeGetRequest(callURI, httpOptions)
            .pipe(
                switchMap((result) => {
                    callURI = piWebAPIUrl + '/streams/' + result[this.resultBody][this.resultWebId] + '/recorded';
                    const requestBody = this.createTestData();

                    //  Create the header for the POST request
                    httpOptions = this.callHeaders(userName, userPassword, authType, true);

                    //  Write the URI we're about to call to the textarea in the UI
                    this.apiResponse.callURIText += '\nPOST Request URI to write the data to the tag: ' + callURI;
                    this.apiResponse.callURIText += '\n\nPOST request body:\n' + JSON.stringify(requestBody, null, 2);

                    //  Make a post request to write the dataset to the recorded streams
                    return this.makePostRequest(callURI, requestBody, httpOptions);
                }),
                map((response) => {
                    this.apiResponse.codeResult = 'Attribute ' + this.sampleTagAttributeName + ' streamed 100 values';
                    this.apiResponse.returnCode = response[this.returnStatus];
                    return this.apiResponse;
                }),
                catchError((error) => {
                    this.apiResponse.codeResult = 'An error occured:  ' + error.message;
                    return of(this.apiResponse);
                })
            );
        } catch (e) {
            this.apiResponse.codeResult = e.message;
            return of(this.apiResponse);
        }
    }

    //  Update an element attribute value
    /**
     * Text goes here
     * @param piWebAPIUrl string: Location of the PI Web API instance
     * @param assetServer  string:  Name of the PI Web API Asset Server (AF)
     * @param userName string:  The user's credentials name
     * @param userPassword  string:  The user's credentials password
     * @param authType string:  The authentication type (basic or kerberos)
     */
    updateAttributeValue(piWebAPIUrl: string, assetServer: string, userName: string, userPassword: string,
                         authType: string): Observable<APIResponse>  {
        try {
            //  Create the header for the GET request
            let httpOptions = this.callHeaders(userName, userPassword, authType, false);
            let callURI: string = piWebAPIUrl + '/attributes?path=\\\\' + assetServer + '\\' + this.databaseName + '\\' +
                                  this.elementName + '|' + this.activeAttributeName;

            //  Write the URI we're about to call to the textarea in the UI
            this.apiResponse.callURIText = 'GET Request URI to retrieve the ' + this.activeAttributeName + ' attribute: ' + callURI;

            //  Get the sample tag's Active attribute
            return this.makeGetRequest(callURI, httpOptions)
            .pipe(
                switchMap((result) => {
                    callURI = result[this.resultBody][this.resultLinks][this.resultValue];

                    //  Construct the request body for the PUT request
                    const requestBody = {
                        Value: true
                    };

                    //  Create the header for the PUT request
                    httpOptions = this.callHeaders(userName, userPassword, authType, true);

                    //  Write the URI we're about to call to the textarea in the UI
                    this.apiResponse.callURIText += '\nPOST Request URI to update the ' + this.activeAttributeName +
                                                    ' attribute value: ' + callURI;
                    this.apiResponse.callURIText += '\n\nPOST request body:\n' + JSON.stringify(requestBody, null, 2);

                    //  Make a post request to update the Active attribute
                    return this.makePutRequest(callURI, requestBody, httpOptions);
                }),
                map((response) => {
                    this.apiResponse.codeResult = 'Attribute ' + this.activeAttributeName + ' value set to true';
                    this.apiResponse.returnCode = response[this.returnStatus];
                    return this.apiResponse;
                }),
                catchError((error) => {
                    this.apiResponse.codeResult = 'An error occured:  ' + error.message;
                    return of(this.apiResponse);
                })
            );
        } catch (e) {
            this.apiResponse.codeResult = e.message;
            return of(this.apiResponse);
        }
    }

    /**
     * Read snapshot value
     * @param piWebAPIUrl string: Location of the PI Web API instance
     * @param assetServer  string:  Name of the PI Web API Asset Server (AF)
     * @param userName string:  The user's credentials name
     * @param userPassword  string:  The user's credentials password
     * @param authType string:  The authentication type (basic or kerberos)
     */
    readSingleValue(piWebAPIUrl: string, assetServer: string, userName: string, userPassword: string,
                    authType: string): Observable<APIResponse>  {
        try {
            const httpOptions = this.callHeaders(userName, userPassword, authType, false);
            let callURI: string = piWebAPIUrl + '/attributes?path=\\\\' + assetServer + '\\' + this.databaseName + '\\' +
                                  this.elementName + '|' + this.sampleTagAttributeName;

            //  Write the URI we're about to call to the textarea in the UI
            this.apiResponse.callURIText = 'GET Request URI to retrieve the ' + this.sampleTagAttributeName + ': ' + callURI;

            //  Get the sample tag
            return this.makeGetRequest(callURI, httpOptions)
            .pipe(
                switchMap((result) => {
                    callURI = piWebAPIUrl + '/streams/' + result[this.resultBody][this.resultWebId] + '/value';
                    //  Write the URI we're about to call to the textarea in the UI
                    this.apiResponse.callURIText += '\nGET Request URI to retrieve the snapshot value: ' + callURI;

                    //  Make a get request to retrieve the snapshot value
                    return this.makeGetRequest(callURI, httpOptions);
                }),
                map((response) => {
                    this.apiResponse.codeResult = this.sampleTagAttributeName + ' Snapshot Value: ' +
                                                  response[this.resultBody][this.resultValue];
                    this.apiResponse.returnCode = response[this.returnStatus];
                    return this.apiResponse;
                }),
                catchError((error) => {
                    this.apiResponse.codeResult = 'An error occured:  ' + error.message;
                    return of(this.apiResponse);
                })
            );
        } catch (e) {
            this.apiResponse.codeResult = e.message;
            return of(this.apiResponse);
        }
    }

    //  Read an attribute stream
    /**
     * Text goes here
     * @param piWebAPIUrl string: Location of the PI Web API instance
     * @param assetServer  string:  Name of the PI Web API Asset Server (AF)
     * @param userName string:  The user's credentials name
     * @param userPassword  string:  The user's credentials password
     * @param authType string:  The authentication type (basic or kerberos)
     */
    readSetOfValues(piWebAPIUrl: string, assetServer: string, userName: string, userPassword: string,
                    authType: string): Observable<APIResponse>  {
        try {
            //  Create the header for the GET request
            const httpOptions = this.callHeaders(userName, userPassword, authType, false);
            let callURI: string = piWebAPIUrl + '/attributes?path=\\\\' + assetServer + '\\' + this.databaseName + '\\' +
                                  this.elementName + '|' + this.sampleTagAttributeName;

            //  Write the URI we're about to call to the textarea in the UI
            this.apiResponse.callURIText = 'GET Request URI to retrieve the ' + this.sampleTagAttributeName + ': ' + callURI;

            //  Get the sample tag
            return this.makeGetRequest(callURI, httpOptions)
            .pipe(
                switchMap((result) => {
                    callURI = piWebAPIUrl + '/streams/' + result[this.resultBody][this.resultWebId] + '/recorded?startTime=*-2d';
                    //  Write the URI we're about to call to the textarea in the UI
                    this.apiResponse.callURIText += '\nGET Request URI to retrieve the recorded values: ' + callURI;

                    //  Make a get request to retrieve the recorded values
                    return this.makeGetRequest(callURI, httpOptions);
                }),
                map((response) => {
                    this.apiResponse.codeResult = this.sampleTagAttributeName + ' Values: ' + JSON.stringify(response, null, 2);
                    this.apiResponse.returnCode = response[this.returnStatus];
                    return this.apiResponse;
                }),
                catchError((error) => {
                    this.apiResponse.codeResult = 'An error occured:  ' + error.message;
                    return of(this.apiResponse);
                })
            );
        } catch (e) {
            this.apiResponse.codeResult = e.message;
            return of(this.apiResponse);
        }
    }

    /**
     * Read sampleTag values with selected fields to reduce payload size
     * @param piWebAPIUrl string: Location of the PI Web API instance
     * @param assetServer  string:  Name of the PI Web API Asset Server (AF)
     * @param userName string:  The user's credentials name
     * @param userPassword  string:  The user's credentials password
     * @param authType string:  The authentication type (basic or kerberos)
     */
    reducePayloadWithSelectedFields(piWebAPIUrl: string, assetServer: string, userName: string, userPassword: string,
                                    authType: string): Observable<APIResponse>  {
        try {
            //  Create the header for the GET request
            const httpOptions = this.callHeaders(userName, userPassword, authType, false);
            let callURI: string = piWebAPIUrl + '/attributes?path=\\\\' + assetServer + '\\' + this.databaseName + '\\' +
                                  this.elementName + '|' + this.sampleTagAttributeName;

            //  Write the URI we're about to call to the textarea in the UI
            this.apiResponse.callURIText = 'GET Request URI to retrieve the ' + this.sampleTagAttributeName + ': ' + callURI;

            //  Get the sample tag
            return this.makeGetRequest(callURI, httpOptions)
            .pipe(
                switchMap((result) => {
                    callURI = piWebAPIUrl + '/streams/' + result[this.resultBody][this.resultWebId] +
                        '/recorded?startTime=*-2d&selectedFields=Items.Timestamp;Items.Value';

                    //  Write the URI we're about to call to the textarea in the UI
                    this.apiResponse.callURIText += '\nGET Request URI to retrieve the recorded values selected fields: ' + callURI;

                    //  Make a get request to retrieve the recorded values - restrict the response to only include the
                    //  TimeStamp and Value fields
                    return this.makeGetRequest(callURI, httpOptions);
                }),
                map((response) => {
                    this.apiResponse.codeResult = this.sampleTagAttributeName + ' Values with Selected Fields: ' +
                                                  JSON.stringify(response, null, 2);
                    this.apiResponse.returnCode = response[this.returnStatus];
                    return this.apiResponse;
                }),
                catchError((error) => {
                    this.apiResponse.codeResult = 'An error occured:  ' + error.message;
                    return of(this.apiResponse);
                })
            );
        } catch (e) {
            this.apiResponse.codeResult = e.message;
            return of(this.apiResponse);
        }
    }

    /**
     * Create and execute a PI Web API Batch call
     * @param piWebAPIUrl string: Location of the PI Web API instance
     * @param assetServer  string:  Name of the PI Web API Asset Server (AF)
     * @param userName string:  The user's credentials name
     * @param userPassword  string:  The user's credentials password
     * @param authType string:  The authentication type (basic or kerberos)
     */
    doBatchCall(piWebAPIUrl: string, assetServer: string, userName: string, userPassword: string,
                authType: string): Observable<APIResponse>  {
        try {
            //  Create the header for the Batch
            let httpOptions = this.callHeaders(userName, userPassword, authType, false);
            let callURI: string = piWebAPIUrl + '/attributes?path=\\\\' + assetServer + '\\' + this.databaseName + '\\' +
                                  this.elementName + '|' + this.sampleTagAttributeName;

            //  Write the URI we're about to call to the textarea in the UI
            this.apiResponse.callURIText = 'GET Request URI to retrieve the ' + this.sampleTagAttributeName + ': ' + callURI;

            //  Get the sample tag
            return this.makeGetRequest(callURI, httpOptions)
            .pipe(
                switchMap((result) => {
                    // Create a single sample value
                    const attributeValue = (Math.random() * 10).toFixed(4);

                    //  Construct the batch request's message body
                    //  1:  Get the sample tag
                    //  2:  Get the sample tag's snapshot value
                    //  3:  Get the sample tag's last 10 recorded values
                    //  4:  Write a snapshot value to the sample tag
                    //  5:  Write a set of recorded values to the sample tag
                    //  6:  Get the sample tag's last 10 recorded values, only returning the value and timestamp
                    const batchRequest = {
                        1: {
                            Method: 'GET',
                            Resource: piWebAPIUrl + '/attributes?path=\\\\' + assetServer + '\\' + this.databaseName + '\\' +
                                      this.elementName + '|' + this.sampleTagAttributeName,
                            Content: '{}'
                        },
                        2: {
                            Method: 'GET',
                            Resource: piWebAPIUrl + '/streams/{0}/value',
                            Content: '{}',
                            Parameters: ['$.1.Content.WebId'],
                            ParentIds: ['1']
                        },
                        3: {
                            Method: 'GET',
                            Resource: piWebAPIUrl + '/streams/{0}/recorded?maxCount=10',
                            Content: '{}',
                            Parameters: ['$.1.Content.WebId'],
                            ParentIds: ['1']
                        },
                        4: {
                            Method: 'PUT',
                            Resource: piWebAPIUrl + '/attributes/{0}/value',
                            Content: '{\'Value\':' + attributeValue + '}',
                            Parameters: ['$.1.Content.WebId'],
                            ParentIds: ['1']
                        },
                        5: {
                            Method: 'POST',
                            Resource: piWebAPIUrl + '/streams/{0}/recorded',
                            Content: '[{\'Value\': \'111\'}, {\'Value\': \'222\'}, {\'Value\': \'333\'}]',
                            Parameters: ['$.1.Content.WebId'],
                            ParentIds: ['1']
                        },
                        6: {
                            Method: 'GET',
                            Resource: piWebAPIUrl + '/streams/{0}/recorded?maxCount=10&selectedFields=Items.Timestamp;Items.Value',
                            Content: '{}',
                            Parameters: ['$.1.Content.WebId'],
                            ParentIds: ['1']
                        }
                    };

                    callURI = piWebAPIUrl + '/batch';

                    //  Create the header for the POST request
                    httpOptions = this.callHeaders(userName, userPassword, authType, true);

                    //  Write the URI we're about to call to the textarea in the UI
                    this.apiResponse.callURIText += '\nPOST Request URI to execute the batch: ' + callURI;
                    this.apiResponse.callURIText += '\n\nPOST request body:\n' + JSON.stringify(batchRequest, null, 2);

                    //  Make a post request to execute the batch
                    return this.makePostRequest(callURI, batchRequest, httpOptions);
                }),
                map((response) => {
                    this.apiResponse.codeResult = JSON.stringify(response, null, 2);
                    this.apiResponse.returnCode = response[this.returnStatus];
                    return this.apiResponse;
                }),
                catchError((error) => {
                    this.apiResponse.codeResult = 'An error occured:  ' + error.message;
                    return of(this.apiResponse);
                })
            );
        } catch (e) {
            this.apiResponse.codeResult = e.message;
            return of(this.apiResponse);
        }
    }

    /**
     * Delete an AF Element
     * @param piWebAPIUrl string: Location of the PI Web API instance
     * @param assetServer  string:  Name of the PI Web API Asset Server (AF)
     * @param userName string:  The user's credentials name
     * @param userPassword  string:  The user's credentials password
     * @param authType string:  The authentication type (basic or kerberos)
     */
    deleteElement(piWebAPIUrl: string, assetServer: string, userName: string, userPassword: string,
                  authType: string): Observable<APIResponse> {
        try {
            //  Create the header for the GET request
            let httpOptions = this.callHeaders(userName, userPassword, authType, false);
            let callURI: string = piWebAPIUrl + '/elements?path=\\\\' + assetServer + '\\' + this.databaseName +
                                  '\\' + this.elementName;

            //  Write the URI we're about to call to the textarea in the UI
            this.apiResponse.callURIText = 'GET Request URI to retrieve the element: ' + callURI;

            //  Get the AF element
            return this.makeGetRequest(callURI, httpOptions)
            .pipe(
                switchMap((result) => {
                    //  Create the header for the DELETE request
                    httpOptions = this.callHeaders(userName, userPassword, authType, true);
                    callURI = result[this.resultBody][this.resultLinks][this.resultSelf];

                    //  Write the URI we're about to call to the textarea in the UI
                    this.apiResponse.callURIText += '\nDELETE Request URI to delete the element: ' + callURI;

                    //  Make a delete request to delete the AF Element
                    return this.makeDeleteRequest(callURI, httpOptions);
                }),
                map((response) => {
                    this.apiResponse.codeResult = 'Element ' + this.elementName + ' Deleted';
                    this.apiResponse.returnCode = response[this.returnStatus];
                    return this.apiResponse;
                }),
                catchError((error) => {
                    this.apiResponse.codeResult = 'An error occured:  ' + error.message;
                    return of(this.apiResponse);
                })
            );
        } catch (e) {
            this.apiResponse.codeResult = e.message;
            return of(this.apiResponse);
        }
    }

    /**
     * Delete an AF Template
     * @param piWebAPIUrl string: Location of the PI Web API instance
     * @param assetServer  string:  Name of the PI Web API Asset Server (AF)
     * @param userName string:  The user's credentials name
     * @param userPassword  string:  The user's credentials password
     * @param authType string:  The authentication type (basic or kerberos)
     */
    deleteTemplate(piWebAPIUrl: string, assetServer: string, userName: string, userPassword: string,
                   authType: string): Observable<APIResponse> {
        try {
            //  Create the header for the GET request
            let httpOptions = this.callHeaders(userName, userPassword, authType, false);
            let callURI: string = piWebAPIUrl + '/elementtemplates?path=\\\\' + assetServer + '\\' + this.databaseName +
                                  '\\ElementTemplates[' + this.templateName + ']';

            //  Write the URI we're about to call to the textarea in the UI
            this.apiResponse.callURIText = 'GET Request URI to retrieve the AF template: ' + callURI;

            //  Get the AF template
            return this.makeGetRequest(callURI, httpOptions)
            .pipe(
                switchMap((result) => {
                    //  Create the header for the DELETE request
                    httpOptions = this.callHeaders(userName, userPassword, authType, true);

                    callURI = piWebAPIUrl + '/elementtemplates/' + result[this.resultBody][this.resultWebId];
                    //  Write the URI we're about to call to the textarea in the UI
                    this.apiResponse.callURIText += '\nDELETE Request URI to delete the AF template: ' + callURI;

                    //  Make a delete request to delete the AF Template
                    return this.makeDeleteRequest(callURI, httpOptions);
                }),
                map((response) => {
                    this.apiResponse.codeResult = 'Template ' + this.templateName + ' deleted';
                    this.apiResponse.returnCode = response[this.returnStatus];
                    return this.apiResponse;
                }),
                catchError((error) => {
                    this.apiResponse.codeResult = 'An error occured:  ' + error.message;
                    return of(this.apiResponse);
                })
            );
        } catch (e) {
            this.apiResponse.codeResult = e.message;
            return of(this.apiResponse);
        }
    }

    /**
     * Delete an AF Category
     * @param piWebAPIUrl string: Location of the PI Web API instance
     * @param assetServer  string:  Name of the PI Web API Asset Server (AF)
     * @param userName string:  The user's credentials name
     * @param userPassword  string:  The user's credentials password
     * @param authType string:  The authentication type (basic or kerberos)
     */
    deleteCategory(piWebAPIUrl: string, assetServer: string, userName: string, userPassword: string,
                   authType: string): Observable<APIResponse> {
        try {
            //  Create the header for the GET request
            let httpOptions = this.callHeaders(userName, userPassword, authType, false);
            let callURI = piWebAPIUrl + '/elementcategories?path=\\\\' + assetServer +
                '\\' + this.databaseName + '\\CategoriesElement[' + this.categoryName + ']';

            //  Write the URI we're about to call to the textarea in the UI
            this.apiResponse.callURIText = 'GET Request URI to retrieve the AF category: ' + callURI;

            //  Get the AF category
            return this.makeGetRequest(callURI, httpOptions)
            .pipe(
                switchMap((result) => {
                    //  Create the header for the DELETE request
                    httpOptions = this.callHeaders(userName, userPassword, authType, true);
                    callURI = result[this.resultBody][this.resultLinks][this.resultSelf];

                    //  Write the URI we're about to call to the textarea in the UI
                    this.apiResponse.callURIText += '\nDELETE Request URI to delete the AF category: ' + callURI;

                    //  Make a delete request to delete the AF Category
                    return this.makeDeleteRequest(callURI, httpOptions);
                }),
                map((response) => {
                    this.apiResponse.codeResult = 'Category ' + this.categoryName + ' deleted';
                    this.apiResponse.returnCode = response[this.returnStatus];
                    return this.apiResponse;
                }),
                catchError((error) => {
                    this.apiResponse.codeResult = 'An error occured:  ' + error.message;
                    return of(this.apiResponse);
                })
            );
        } catch (e) {
            this.apiResponse.codeResult = e.message;
            return of(this.apiResponse);
        }
    }

    /**
     * Delete the Angular Web API Sample database
     * @param piWebAPIUrl string: Location of the PI Web API instance
     * @param assetServer  string:  Name of the PI Web API Asset Server (AF)
     * @param userName string:  The user's credentials name
     * @param userPassword  string:  The user's credentials password
     * @param authType string:  The authentication type (basic or kerberos)
     */
    deleteDatabase(piWebAPIUrl: string, assetServer: string, userName: string, userPassword: string,
                   authType: string): Observable<APIResponse>  {
        try {
            //  Create the header for the GET request
            let httpOptions = this.callHeaders(userName, userPassword, authType, false);
            let callURI: string = piWebAPIUrl + '/assetdatabases?path=\\\\' + assetServer + '\\' + this.databaseName;

            //  Write the URI we're about to call to the textarea in the UI
            this.apiResponse.callURIText = 'GET request URI to retrieve the database: ' + callURI;

            //  Get the database we want to delete
            return this.makeGetRequest(callURI, httpOptions)
            .pipe(
                switchMap((result) => {
                    //  Create the header for the DELETE request
                    httpOptions = this.callHeaders(userName, userPassword, authType, true);
                    callURI = piWebAPIUrl + '/assetdatabases/' + result[this.resultBody][this.resultWebId];

                    //  Write the URI we're about to call to the textarea in the UI
                    this.apiResponse.callURIText += '\nDELETE request URI to delete the database: ' + callURI;

                    //  Make a delete request to delete the database
                    return this.makeDeleteRequest(callURI, httpOptions);
                }),
                map((response) => {
                    this.apiResponse.codeResult = 'Database ' + this.databaseName + ' deleted';
                    this.apiResponse.returnCode = response[this.returnStatus];
                    return this.apiResponse;
                }),
                catchError((error) => {
                    this.apiResponse.codeResult = 'An error occured:  ' + error.message;
                    return of(this.apiResponse);
                })
            );
        } catch (e) {
            this.apiResponse.codeResult = e.message;
            return of(this.apiResponse);
        }
    }

    /**
     * Make a GET request with the HTTPClient
     * @param callURI string: PI Web API URI for the call
     * @param httpOptions  HTTP Header and authorization information
     */
    makeGetRequest(callURI: string, httpOptions) {
        return this.httpClient.get(callURI, httpOptions);
    }

    /**
     * Make a POST request with the HTTPClient
     * @param callURI string: PI Web API URI for the call
     * @param requestBody JSON request body
     * @param httpOptions  HTTP Header and authorization information
     */
    makePostRequest(callURI: string, requestBody, httpOptions) {
        return this.httpClient.post(callURI, requestBody, httpOptions);
    }

    /**
     * Make a DELETE request with the HTTPClient
     * @param callURI string: PI Web API URI for the call
     * @param httpOptions  HTTP Header and authorization information
     */
    makeDeleteRequest(callURI: string, httpOptions) {
        return this.httpClient.delete(callURI, httpOptions);
    }

    /**
     * Make a PUT request with the HTTPClient
     * @param callURI string: PI Web API URI for the call
     * @param requestBody JSON request body
     * @param httpOptions  HTTP Header and authorization information
     */
    makePutRequest(callURI: string, requestBody, httpOptions) {
        return this.httpClient.put(callURI, requestBody, httpOptions);
    }

}


