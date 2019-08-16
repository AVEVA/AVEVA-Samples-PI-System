import { TestBed } from '@angular/core/testing';
import { PIWebAPIService } from './piwebapi.service';
import { HttpClientModule } from '@angular/common/http';

// Increase timeout interval for longer running http calls.
// jasmine.DEFAULT_TIMEOUT_INTERVAL = 10000;

describe('Service: PIWebAPIService', () => {

    let testService: PIWebAPIService;

    beforeEach(() => {
        TestBed.configureTestingModule({
            imports: [HttpClientModule],
            providers: [PIWebAPIService]
        });
        testService = TestBed.get(PIWebAPIService);
    });

    const piWebAPIUrl = '';
    const assetServer = '';
    const piServer = '';
    const userName = '';
    const userPassword = '';
    const authType = '';

    it('PIWebAPIService should be created', () => {
      expect(testService).toBeTruthy();
    });

    /**
     * Test the createDatabase method
     */
    it('creating a new database should return a 201', (done) => {
        //  make the createDatabase call and make sure the return code matches what we expect - 201
        testService.createDatabase(piWebAPIUrl, assetServer, userName, userPassword, authType).subscribe((response) => {
            expect(response.returnCode).toEqual(201);
            done();
        });
    });

    /**
     * Test the createCategory method
     */
    it('creating a new category should return a 201', (done) => {
        //  make the createCategory call and make sure the return code matches what we expect - 201
        testService.createCategory(piWebAPIUrl, assetServer, userName, userPassword, authType).subscribe((response) => {
            expect(response.returnCode).toEqual(201);
            done();
        });
    });

    /**
     * Test the createTemplate method
     */
    it('creating a new template should return a 201', (done) => {
        //  make the createTemplate call and make sure the return code matches what we expect - 201
        testService.createTemplate(piWebAPIUrl, assetServer, piServer, userName, userPassword, authType).subscribe((response) => {
            expect(response.returnCode).toEqual(201);
            done();
        });
    });

    /**
     * Test the createElement method
     */
    it('creating a new element should return a 200', (done) => {
        //  make the createElement call and make sure the return code matches what we expect - 200
        testService.createElement(piWebAPIUrl, assetServer, userName, userPassword, authType).subscribe((response) => {
            expect(response.returnCode).toEqual(200);
            done();
        });
    });

    /**
     * Test the writeSingleValue method
     */
    it('writing a single value should return a 202', (done) => {
        //  make the writeSingleValue call and make sure the return code matches what we expect - 202
        testService.writeSingleValue(piWebAPIUrl, assetServer, userName, userPassword, authType).subscribe((response) => {
            expect(response.returnCode).toEqual(202);
            done();
        });
    });

    /**
     * Test the writeSetOfValues method
     */
    it('writing a set of values should return a 202', (done) => {
        //  make the writeSetOfValues call and make sure the return code matches what we expect - 202
        testService.writeSetOfValues(piWebAPIUrl, assetServer, userName, userPassword, authType).subscribe((response) => {
            expect(response.returnCode).toEqual(202);
            done();
        });
    });

    /**
     * Test the updateAttributeValue method
     */
    it('updating an attribute value should return a 204', (done) => {
        //  make the updateAttributeValue call and make sure the return code matches what we expect - 204
        testService.updateAttributeValue(piWebAPIUrl, assetServer, userName, userPassword, authType).subscribe((response) => {
            expect(response.returnCode).toEqual(204);
            done();
        });
    });

    /**
     * Test the readSingleValue method
     */
    it('reading a single value should return a 200', (done) => {
        //  make the readSingleValue call and make sure the return code matches what we expect - 200
        testService.readSingleValue(piWebAPIUrl, assetServer, userName, userPassword, authType).subscribe((response) => {
            expect(response.returnCode).toEqual(200);
            done();
        });
    });

    /**
     * Test the readSetOfValues method
     */
    it('reading a set of values should return a 200', (done) => {
        //  make the readSetOfValues call and make sure the return code matches what we expect - 200
        testService.readSetOfValues(piWebAPIUrl, assetServer, userName, userPassword, authType).subscribe((response) => {
            expect(response.returnCode).toEqual(200);
            done();
        });
    });

    /**
     * Test the reducePayloadWithSelectedFields method
     */
    it('reading a set of values while reducing payload with selected fields should return a 200', (done) => {
        //  make the reducePayloadWithSelectedFields call and make sure the return code matches what we expect - 200
        testService.reducePayloadWithSelectedFields(piWebAPIUrl, assetServer, userName, userPassword, authType).subscribe((response) => {
            expect(response.returnCode).toEqual(200);
            done();
        });
    });

    /**
     * Test the doBatchCall method
     */
    it('performing a batch call should return a 207', (done) => {
        //  make the doBatchCall call and make sure the return code matches what we expect - 207
        testService.doBatchCall(piWebAPIUrl, assetServer, userName, userPassword, authType).subscribe((response) => {
            expect(response.returnCode).toEqual(207);
            done();
        });
    });

    /**
     * Test the deleteElement method
     */
    it('deleting an element should return a 204', (done) => {
        //  make the deleteElement call and make sure the return code matches what we expect - 204
        testService.deleteElement(piWebAPIUrl, assetServer, userName, userPassword, authType).subscribe((response) => {
            expect(response.returnCode).toEqual(204);
            done();
        });
    });

    /**
     * Test the deleteTemplate method
     */
    it('deleting a template should return a 204', (done) => {
        //  make the deleteTemplate call and make sure the return code matches what we expect - 204
        testService.deleteTemplate(piWebAPIUrl, assetServer, userName, userPassword, authType).subscribe((response) => {
            expect(response.returnCode).toEqual(204);
            done();
        });
    });

    /**
     * Test the deleteCategory method
     */
    it('deleting a category should return a 204', (done) => {
        //  make the deleteCategory call and make sure the return code matches what we expect - 204
        testService.deleteCategory(piWebAPIUrl, assetServer, userName, userPassword, authType).subscribe((response) => {
            expect(response.returnCode).toEqual(204);
            done();
        });
    });

    /**
     * Test the deleteDatabase method
     */
    it('deleting a database should return a 204', (done) => {
        //  make the deleteDatabase call and make sure the return code matches what we expect - 204
        testService.deleteDatabase(piWebAPIUrl, assetServer, userName, userPassword, authType).subscribe((response) => {
            expect(response.returnCode).toEqual(204);
            done();
        });
    });
});

