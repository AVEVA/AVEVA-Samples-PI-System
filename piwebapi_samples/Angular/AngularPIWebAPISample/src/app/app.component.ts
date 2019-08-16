import { Component, OnInit } from '@angular/core';
import { PIWebAPIService } from './services/piwebapi.service';

/*
  This angular app requires some pre-requisites:
  1.  Node.js and npm installed.
          If that's not the case go to the official website and download the latest version for your operating system
  2.  A back-end server with PI WEB API with CORS enabled.
  3.  You also need to have the Angular CLI v7 installed:
          $ npm install -g @angular/cli
  4.  Install dependencies
          npm install
*/

@Component({
  selector: 'app-root',
  templateUrl: './app.component.html',
  styleUrls: ['./app.component.css']
})

export class AppComponent implements OnInit {
  title = 'Angular PI Web API Calls';
  //  Set up the UI values
  userName = '';
  userPassword = '';
  PIWebAPIUrl = '';
  assetServer = '';
  piServer = '';
  securityMethod = 'basic';
  selectedCallOption = 'createDatabase';
  codeResult = '';
  callURIText = '';

  securityMethods = [
    { id: 'basic', name: 'Basic' },
    { id: 'kerberos', name: 'Kerberos' }
  ];

  callOptions = [
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
    { id: 'payloadselectedfields', name: 'Reduce Payload with Selected Fields' },
    { id: 'batch', name: 'Batch Writes and Reads' },
    { id: 'divider', name: '-----------------------' },
    { id: 'deleteelement', name: 'Delete Element' },
    { id: 'deletetemplate', name: 'Delete Template' },
    { id: 'deletecategory', name: 'Delete Category' },
    { id: 'deletedatabase', name: 'Delete Database' }
  ];

  constructor(private piWebAPIService: PIWebAPIService) { this.ngOnInit(); }

  ngOnInit() {
    this.codeResult = '';
    this.callURIText = '';
  }

  /**
   * The onChange event triggers when the Action is changed in the drop down
   * @param event the event of the drop down value change
   */
  onChange(event): void {
    this.selectedCallOption = event.target.value;
  }

  /**
   * The onChange event triggers when the security method is changed in the drop down
   * @param event the event of the drop down value change
   */
  onSecurityChange(event): void {
    this.securityMethod = event.target.value;
  }

  createDatabase(PIWebAPIUrl, assetServer, userName, userPassword, securityMethod) {
    this.piWebAPIService.createDatabase(PIWebAPIUrl, assetServer, userName, userPassword,
      securityMethod).subscribe((response) => {
        this.callURIText = response.callURIText;
        this.codeResult = response.codeResult;
      });
  }

  /**
   * Button click event
   */
  onButtonClick() {
    let apiAction;
    try {
      switch (this.selectedCallOption) {
        case 'createDatabase': {
          apiAction = this.piWebAPIService.createDatabase(this.PIWebAPIUrl, this.assetServer, this.userName,
            this.userPassword, this.securityMethod);
          break;
        }
        case 'createcategory': {
          apiAction = this.piWebAPIService.createCategory(this.PIWebAPIUrl, this.assetServer, this.userName,
            this.userPassword, this.securityMethod);
          break;
        }
        case 'createtemplate': {
          apiAction = this.piWebAPIService.createTemplate(this.PIWebAPIUrl, this.assetServer, this.piServer,
            this.userName, this.userPassword, this.securityMethod);
          break;
        }
        case 'createelement': {
          apiAction = this.piWebAPIService.createElement(this.PIWebAPIUrl, this.assetServer, this.userName,
            this.userPassword, this.securityMethod);
          break;
        }
        case 'deleteelement': {
          apiAction = this.piWebAPIService.deleteElement(this.PIWebAPIUrl, this.assetServer, this.userName,
            this.userPassword, this.securityMethod);
          break;
        }
        case 'deletetemplate': {
          apiAction = this.piWebAPIService.deleteTemplate(this.PIWebAPIUrl, this.assetServer, this.userName,
            this.userPassword, this.securityMethod);
          break;
        }
        case 'deletecategory': {
          apiAction = this.piWebAPIService.deleteCategory(this.PIWebAPIUrl, this.assetServer, this.userName,
            this.userPassword, this.securityMethod);
          break;
        }
        case 'deletedatabase': {
          apiAction = this.piWebAPIService.deleteDatabase(this.PIWebAPIUrl, this.assetServer, this.userName,
            this.userPassword, this.securityMethod);
          break;
        }
        case 'writesinglevalue': {
          apiAction = this.piWebAPIService.writeSingleValue(this.PIWebAPIUrl, this.assetServer, this.userName,
            this.userPassword, this.securityMethod);
          break;
        }
        case 'writerecordedvalues': {
          apiAction = this.piWebAPIService.writeSetOfValues(this.PIWebAPIUrl, this.assetServer, this.userName,
            this.userPassword, this.securityMethod);
          break;
        }
        case 'updatevalue': {
          apiAction = this.piWebAPIService.updateAttributeValue(this.PIWebAPIUrl, this.assetServer, this.userName,
            this.userPassword, this.securityMethod);
          break;
        }
        case 'getsnapshotvalue': {
          apiAction = this.piWebAPIService.readSingleValue(this.PIWebAPIUrl, this.assetServer, this.userName,
            this.userPassword, this.securityMethod);
          break;
        }
        case 'getrecordedvalues': {
          apiAction = this.piWebAPIService.readSetOfValues(this.PIWebAPIUrl, this.assetServer, this.userName,
            this.userPassword, this.securityMethod);
          break;
        }
        case 'payloadselectedfields': {
          apiAction = this.piWebAPIService.reducePayloadWithSelectedFields(this.PIWebAPIUrl, this.assetServer,
            this.userName, this.userPassword, this.securityMethod);
          break;
        }
        case 'batch': {
          apiAction = this.piWebAPIService.doBatchCall(this.PIWebAPIUrl, this.assetServer, this.userName,
            this.userPassword, this.securityMethod);
          break;
        }

        default: {
          break;
        }
      }
      apiAction.subscribe((response) => {
        this.callURIText = response.callURIText;
        this.codeResult = response.codeResult;
      });
    } catch (e) {
      console.log('An error occured: ' + e);
    }
  }
}

