import { TestBed } from '@angular/core/testing';
import { HttpClientModule } from '@angular/common/http';

import { PIWebAPIService } from './piwebapi.service';
import { testConfig } from '../../../test-config';

// Increase timeout interval for longer running http calls.
if (testConfig.DEFAULT_TIMEOUT_INTERVAL) {
  jasmine.DEFAULT_TIMEOUT_INTERVAL = testConfig.DEFAULT_TIMEOUT_INTERVAL;
}

describe('Service: PIWebAPIService', () => {
  let testService: PIWebAPIService;

  beforeEach(() => {
    TestBed.configureTestingModule({
      imports: [HttpClientModule],
      providers: [PIWebAPIService]
    });
    testService = TestBed.get(PIWebAPIService);
  });

  it('PIWebAPIService should be created', () => {
    expect(testService).toBeTruthy();
  });

  /**
   * Test the createDatabase method
   */
  it('creating a new database should return a 201', done => {
    //  make the createDatabase call and make sure the return code matches what we expect - 201
    testService
      .createDatabase(
        testConfig.piWebApiUrl,
        testConfig.assetServer,
        testConfig.userName,
        testConfig.userPassword,
        testConfig.authType
      )
      .subscribe(response => {
        expect(response.returnCode).toEqual(201);
        done();
      });
  });

  /**
   * Test the createCategory method
   */
  it('creating a new category should return a 201', done => {
    //  make the createCategory call and make sure the return code matches what we expect - 201
    testService
      .createCategory(
        testConfig.piWebApiUrl,
        testConfig.assetServer,
        testConfig.userName,
        testConfig.userPassword,
        testConfig.authType
      )
      .subscribe(response => {
        expect(response.returnCode).toEqual(201);
        done();
      });
  });

  /**
   * Test the createTemplate method
   */
  it('creating a new template should return a 201', done => {
    //  make the createTemplate call and make sure the return code matches what we expect - 201
    testService
      .createTemplate(
        testConfig.piWebApiUrl,
        testConfig.assetServer,
        testConfig.piServer,
        testConfig.userName,
        testConfig.userPassword,
        testConfig.authType
      )
      .subscribe(response => {
        expect(response.returnCode).toEqual(201);
        done();
      });
  });

  /**
   * Test the createElement method
   */
  it('creating a new element should return a 200', done => {
    //  make the createElement call and make sure the return code matches what we expect - 200
    testService
      .createElement(
        testConfig.piWebApiUrl,
        testConfig.assetServer,
        testConfig.userName,
        testConfig.userPassword,
        testConfig.authType
      )
      .subscribe(response => {
        expect(response.returnCode).toEqual(200);
        done();
      });
  });

  /**
   * Test the writeSingleValue method
   */
  it('writing a single value should return a 202', done => {
    //  make the writeSingleValue call and make sure the return code matches what we expect - 202
    testService
      .writeSingleValue(
        testConfig.piWebApiUrl,
        testConfig.assetServer,
        testConfig.userName,
        testConfig.userPassword,
        testConfig.authType
      )
      .subscribe(response => {
        expect(response.returnCode).toEqual(202);
        done();
      });
  });

  /**
   * Test the writeSetOfValues method
   */
  it('writing a set of values should return a 202', done => {
    //  make the writeSetOfValues call and make sure the return code matches what we expect - 202
    testService
      .writeSetOfValues(
        testConfig.piWebApiUrl,
        testConfig.assetServer,
        testConfig.userName,
        testConfig.userPassword,
        testConfig.authType
      )
      .subscribe(response => {
        expect(response.returnCode).toEqual(202);
        done();
      });
  });

  /**
   * Test the updateAttributeValue method
   */
  it('updating an attribute value should return a 204', done => {
    //  make the updateAttributeValue call and make sure the return code matches what we expect - 204
    testService
      .updateAttributeValue(
        testConfig.piWebApiUrl,
        testConfig.assetServer,
        testConfig.userName,
        testConfig.userPassword,
        testConfig.authType
      )
      .subscribe(response => {
        expect(response.returnCode).toEqual(204);
        done();
      });
  });

  /**
   * Test the readSingleValue method
   */
  it('reading a single value should return a 200', done => {
    //  make the readSingleValue call and make sure the return code matches what we expect - 200
    testService
      .readSingleValue(
        testConfig.piWebApiUrl,
        testConfig.assetServer,
        testConfig.userName,
        testConfig.userPassword,
        testConfig.authType
      )
      .subscribe(response => {
        expect(response.returnCode).toEqual(200);
        done();
      });
  });

  /**
   * Test the readSetOfValues method
   */
  it('reading a set of values should return a 200', done => {
    //  make the readSetOfValues call and make sure the return code matches what we expect - 200
    testService
      .readSetOfValues(
        testConfig.piWebApiUrl,
        testConfig.assetServer,
        testConfig.userName,
        testConfig.userPassword,
        testConfig.authType
      )
      .subscribe(response => {
        expect(response.returnCode).toEqual(200);
        done();
      });
  });

  /**
   * Test the reducePayloadWithSelectedFields method
   */
  it('reading a set of values while reducing payload with selected fields should return a 200', done => {
    //  make the reducePayloadWithSelectedFields call and make sure the return code matches what we expect - 200
    testService
      .reducePayloadWithSelectedFields(
        testConfig.piWebApiUrl,
        testConfig.assetServer,
        testConfig.userName,
        testConfig.userPassword,
        testConfig.authType
      )
      .subscribe(response => {
        expect(response.returnCode).toEqual(200);
        done();
      });
  });

  /**
   * Test the doBatchCall method
   */
  it('performing a batch call should return a 207', done => {
    //  make the doBatchCall call and make sure the return code matches what we expect - 207
    testService
      .doBatchCall(
        testConfig.piWebApiUrl,
        testConfig.assetServer,
        testConfig.userName,
        testConfig.userPassword,
        testConfig.authType
      )
      .subscribe(response => {
        expect(response.returnCode).toEqual(207);
        done();
      });
  });

  /**
   * Test the deleteElement method
   */
  it('deleting an element should return a 204', done => {
    //  make the deleteElement call and make sure the return code matches what we expect - 204
    testService
      .deleteElement(
        testConfig.piWebApiUrl,
        testConfig.assetServer,
        testConfig.userName,
        testConfig.userPassword,
        testConfig.authType
      )
      .subscribe(response => {
        expect(response.returnCode).toEqual(204);
        done();
      });
  });

  /**
   * Test the deleteTemplate method
   */
  it('deleting a template should return a 204', done => {
    //  make the deleteTemplate call and make sure the return code matches what we expect - 204
    testService
      .deleteTemplate(
        testConfig.piWebApiUrl,
        testConfig.assetServer,
        testConfig.userName,
        testConfig.userPassword,
        testConfig.authType
      )
      .subscribe(response => {
        expect(response.returnCode).toEqual(204);
        done();
      });
  });

  /**
   * Test the deleteCategory method
   */
  it('deleting a category should return a 204', done => {
    //  make the deleteCategory call and make sure the return code matches what we expect - 204
    testService
      .deleteCategory(
        testConfig.piWebApiUrl,
        testConfig.assetServer,
        testConfig.userName,
        testConfig.userPassword,
        testConfig.authType
      )
      .subscribe(response => {
        expect(response.returnCode).toEqual(204);
        done();
      });
  });

  /**
   * Test the deleteDatabase method
   */
  it('deleting a database should return a 204', done => {
    //  make the deleteDatabase call and make sure the return code matches what we expect - 204
    testService
      .deleteDatabase(
        testConfig.piWebApiUrl,
        testConfig.assetServer,
        testConfig.userName,
        testConfig.userPassword,
        testConfig.authType
      )
      .subscribe(response => {
        expect(response.returnCode).toEqual(204);
        done();
      });
  });
});
