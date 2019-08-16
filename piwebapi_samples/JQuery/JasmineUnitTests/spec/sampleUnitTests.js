
$(document).ready(function () {
    jasmine.DEFAULT_TIMEOUT_INTERVAL = 40000
    $.ajaxSetup({async: false})
    deleteDatabase(configDefaults.PIWebAPIUrl, configDefaults.AssetServer, configDefaults.Name, configDefaults.Password, configDefaults.AuthType)
    $.ajaxSetup({async: true})
})

describe('Create test environment', function () {
    it('createTestData', function () {
        $.ajaxSetup({async: false})
        var testData = createTestData()
        $.ajaxSetup({async: true})
        expect(testData.length).toEqual(100)
    })

    it('createDatabase', function () {
        $.ajaxSetup({async: false})
        var statusCode = createDatabase(configDefaults.PIWebAPIUrl, configDefaults.AssetServer, configDefaults.Name, configDefaults.Password, configDefaults.AuthType)
        $.ajaxSetup({async: true})
        expect(statusCode).toEqual(201)
    })

    it('createCategory', function () {
        $.ajaxSetup({async: false})
        var statusCode = createCategory(configDefaults.PIWebAPIUrl, configDefaults.AssetServer, configDefaults.Name, configDefaults.Password, configDefaults.AuthType)
        $.ajaxSetup({async: true})
        expect(statusCode).toEqual(201)
      })

    it('createTemplate', function () {
        $.ajaxSetup({async: false})
        var statusCode = createTemplate(configDefaults.PIWebAPIUrl, configDefaults.AssetServer, configDefaults.PIServer, configDefaults.Name, configDefaults.Password, configDefaults.AuthType)
        $.ajaxSetup({async: true})
        expect(statusCode).toEqual(200)
    })

    it('createElement', function () {
        $.ajaxSetup({async: false})
        var statusCode = createElement(configDefaults.PIWebAPIUrl, configDefaults.AssetServer, configDefaults.Name, configDefaults.Password, configDefaults.AuthType)
        $.ajaxSetup({async: true})
        expect(statusCode).toEqual(201)
    })
})

describe('Read/write tests', function () {

    it('doBatchCall', function () {
        $.ajaxSetup({async: false})
        var statusCode = doBatchCall(configDefaults.PIWebAPIUrl, configDefaults.AssetServer, configDefaults.Name, configDefaults.Password, configDefaults.AuthType)
        $.ajaxSetup({async: true})
        expect(statusCode).toEqual(207)
    })

    it('readAttributeSelectedFields', function () {
        $.ajaxSetup({async: false})
        var statusCode = readAttributeSelectedFields(configDefaults.PIWebAPIUrl, configDefaults.AssetServer, configDefaults.Name, configDefaults.Password, configDefaults.AuthType)
        $.ajaxSetup({async: true})
        expect(statusCode).toEqual(200)
    })

    it('readAttributeSnapshot', function () {
        $.ajaxSetup({async: false})
        var statusCode = readAttributeSnapshot(configDefaults.PIWebAPIUrl, configDefaults.AssetServer, configDefaults.Name, configDefaults.Password, configDefaults.AuthType)
        $.ajaxSetup({async: true})
        expect(statusCode).toEqual(200)
    })

    it('readAttributeStream', function () {
        $.ajaxSetup({async: false})
        var statusCode = readAttributeStream(configDefaults.PIWebAPIUrl, configDefaults.AssetServer, configDefaults.Name, configDefaults.Password, configDefaults.AuthType)
        $.ajaxSetup({async: true})
        expect(statusCode).toEqual(200)
    })

    it('writeDataSet', function () {
        $.ajaxSetup({async: false})
        var statusCode = writeDataSet(configDefaults.PIWebAPIUrl, configDefaults.AssetServer, configDefaults.Name, configDefaults.Password, configDefaults.AuthType)
        $.ajaxSetup({async: true})
        expect(statusCode === 202 || statusCode === 207).toEqual(true)
    })

    it('writeSingleValue', function () {
        $.ajaxSetup({async: false})
        var statusCode = writeSingleValue(configDefaults.PIWebAPIUrl, configDefaults.AssetServer, configDefaults.Name, configDefaults.Password, configDefaults.AuthType)
        $.ajaxSetup({async: true})
        expect(statusCode).toEqual(204)
    })

    it('updateAttributeValue', function () {
        $.ajaxSetup({async: false})
        var statusCode = updateAttributeValue(configDefaults.PIWebAPIUrl, configDefaults.AssetServer, configDefaults.Name, configDefaults.Password, configDefaults.AuthType)
        $.ajaxSetup({async: true})
        expect(statusCode).toEqual(204)
    })
})

describe('Delete test environment', function () {
    it('deleteElement', function () {
        $.ajaxSetup({async: false})
        var statusCode = deleteElement(configDefaults.PIWebAPIUrl, configDefaults.AssetServer, configDefaults.Name, configDefaults.Password, configDefaults.AuthType)
        $.ajaxSetup({async: true})
        expect(statusCode).toEqual(204)
    })

    it('deleteTemplate', function () {
        $.ajaxSetup({async: false})
        var statusCode = deleteTemplate(configDefaults.PIWebAPIUrl, configDefaults.AssetServer, configDefaults.Name, configDefaults.Password, configDefaults.AuthType)
        $.ajaxSetup({async: true})
        expect(statusCode).toEqual(200)
    })

    it('deleteCategory', function () {
        $.ajaxSetup({async: false})
        var statusCode = deleteCategory(configDefaults.PIWebAPIUrl, configDefaults.AssetServer, configDefaults.Name, configDefaults.Password, configDefaults.AuthType)
        $.ajaxSetup({async: true})
        expect(statusCode).toEqual(200)
    })

    it('deleteDatabase', function () {
        $.ajaxSetup({async: false})
        var statusCode = deleteDatabase(configDefaults.PIWebAPIUrl, configDefaults.AssetServer, configDefaults.Name, configDefaults.Password, configDefaults.AuthType)
        $.ajaxSetup({async: true})
        expect(statusCode).toEqual(200)
    })
})