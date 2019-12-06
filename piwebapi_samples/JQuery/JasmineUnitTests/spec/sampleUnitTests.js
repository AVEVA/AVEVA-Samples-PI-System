$(document).ready(function() {
  if (testConfig.DEFAULT_TIMEOUT_INTERVAL) {
    jasmine.DEFAULT_TIMEOUT_INTERVAL = testConfig.DEFAULT_TIMEOUT_INTERVAL;
  }
  $.ajaxSetup({ async: false });
  deleteDatabase(
    testConfig.piWebApiUrl,
    testConfig.assetServer,
    testConfig.userName,
    testConfig.userPassword,
    testConfig.authType
  );
  $.ajaxSetup({ async: true });
});

describe('Create test environment', function() {
  it('createTestData', function() {
    $.ajaxSetup({ async: false });
    var testData = createTestData();
    $.ajaxSetup({ async: true });
    expect(testData.length).toEqual(100);
  });

  it('createDatabase', function() {
    $.ajaxSetup({ async: false });
    var statusCode = createDatabase(
      testConfig.piWebApiUrl,
      testConfig.assetServer,
      testConfig.userName,
      testConfig.userPassword,
      testConfig.authType
    );
    $.ajaxSetup({ async: true });
    expect(statusCode).toEqual(201);
  });

  it('createCategory', function() {
    $.ajaxSetup({ async: false });
    var statusCode = createCategory(
      testConfig.piWebApiUrl,
      testConfig.assetServer,
      testConfig.userName,
      testConfig.userPassword,
      testConfig.authType
    );
    $.ajaxSetup({ async: true });
    expect(statusCode).toEqual(201);
  });

  it('createTemplate', function() {
    $.ajaxSetup({ async: false });
    var statusCode = createTemplate(
      testConfig.piWebApiUrl,
      testConfig.assetServer,
      testConfig.piServer,
      testConfig.userName,
      testConfig.userPassword,
      testConfig.authType
    );
    $.ajaxSetup({ async: true });
    expect(statusCode).toEqual(200);
  });

  it('createElement', function() {
    $.ajaxSetup({ async: false });
    var statusCode = createElement(
      testConfig.piWebApiUrl,
      testConfig.assetServer,
      testConfig.userName,
      testConfig.userPassword,
      testConfig.authType
    );
    $.ajaxSetup({ async: true });
    expect(statusCode).toEqual(201);
  });
});

describe('Read/write tests', function() {
  it('doBatchCall', function() {
    $.ajaxSetup({ async: false });
    var statusCode = doBatchCall(
      testConfig.piWebApiUrl,
      testConfig.assetServer,
      testConfig.userName,
      testConfig.userPassword,
      testConfig.authType
    );
    $.ajaxSetup({ async: true });
    expect(statusCode).toEqual(207);
  });

  it('readAttributeSelectedFields', function() {
    $.ajaxSetup({ async: false });
    var statusCode = readAttributeSelectedFields(
      testConfig.piWebApiUrl,
      testConfig.assetServer,
      testConfig.userName,
      testConfig.userPassword,
      testConfig.authType
    );
    $.ajaxSetup({ async: true });
    expect(statusCode).toEqual(200);
  });

  it('readAttributeSnapshot', function() {
    $.ajaxSetup({ async: false });
    var statusCode = readAttributeSnapshot(
      testConfig.piWebApiUrl,
      testConfig.assetServer,
      testConfig.userName,
      testConfig.userPassword,
      testConfig.authType
    );
    $.ajaxSetup({ async: true });
    expect(statusCode).toEqual(200);
  });

  it('readAttributeStream', function() {
    $.ajaxSetup({ async: false });
    var statusCode = readAttributeStream(
      testConfig.piWebApiUrl,
      testConfig.assetServer,
      testConfig.userName,
      testConfig.userPassword,
      testConfig.authType
    );
    $.ajaxSetup({ async: true });
    expect(statusCode).toEqual(200);
  });

  it('writeDataSet', function() {
    $.ajaxSetup({ async: false });
    var statusCode = writeDataSet(
      testConfig.piWebApiUrl,
      testConfig.assetServer,
      testConfig.userName,
      testConfig.userPassword,
      testConfig.authType
    );
    $.ajaxSetup({ async: true });
    expect(statusCode === 202 || statusCode === 207).toEqual(true);
  });

  it('writeSingleValue', function() {
    $.ajaxSetup({ async: false });
    var statusCode = writeSingleValue(
      testConfig.piWebApiUrl,
      testConfig.assetServer,
      testConfig.userName,
      testConfig.userPassword,
      testConfig.authType
    );
    $.ajaxSetup({ async: true });
    expect(statusCode).toEqual(204);
  });

  it('updateAttributeValue', function() {
    $.ajaxSetup({ async: false });
    var statusCode = updateAttributeValue(
      testConfig.piWebApiUrl,
      testConfig.assetServer,
      testConfig.userName,
      testConfig.userPassword,
      testConfig.authType
    );
    $.ajaxSetup({ async: true });
    expect(statusCode).toEqual(204);
  });
});

describe('Delete test environment', function() {
  it('deleteElement', function() {
    $.ajaxSetup({ async: false });
    var statusCode = deleteElement(
      testConfig.piWebApiUrl,
      testConfig.assetServer,
      testConfig.userName,
      testConfig.userPassword,
      testConfig.authType
    );
    $.ajaxSetup({ async: true });
    expect(statusCode).toEqual(204);
  });

  it('deleteTemplate', function() {
    $.ajaxSetup({ async: false });
    var statusCode = deleteTemplate(
      testConfig.piWebApiUrl,
      testConfig.assetServer,
      testConfig.userName,
      testConfig.userPassword,
      testConfig.authType
    );
    $.ajaxSetup({ async: true });
    expect(statusCode).toEqual(200);
  });

  it('deleteCategory', function() {
    $.ajaxSetup({ async: false });
    var statusCode = deleteCategory(
      testConfig.piWebApiUrl,
      testConfig.assetServer,
      testConfig.userName,
      testConfig.userPassword,
      testConfig.authType
    );
    $.ajaxSetup({ async: true });
    expect(statusCode).toEqual(200);
  });

  it('deleteDatabase', function() {
    $.ajaxSetup({ async: false });
    var statusCode = deleteDatabase(
      testConfig.piWebApiUrl,
      testConfig.assetServer,
      testConfig.userName,
      testConfig.userPassword,
      testConfig.authType
    );
    $.ajaxSetup({ async: true });
    expect(statusCode).toEqual(200);
  });
});
