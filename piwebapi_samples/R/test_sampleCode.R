
require("testthat")
source('sampleCode.R')

#Setup for unit tests
deleteDatabase(defaultPIWebAPIUrl, defaultAssetServer, defaultName, defaultPassword, defaultAuthorization)

#UI test
test_that("runPIWebAPISamples", {
  dlg <- runPIWebAPISamples()
  expect_type(dlg, "list")
  tkdestroy(dlg)
})

#AF database creation tests
test_that("createTestData", {
  df <- createTestData()
  expect_equal(ncol(df), 2)
  expect_equal(nrow(df), 100)
})

test_that("createDatabase", {
  statusCode <- createDatabase(defaultPIWebAPIUrl, defaultAssetServer, defaultName, defaultPassword, defaultAuthorization)
  expect_equal(statusCode, 201)
})

test_that("createCategory", {
  statusCode <- createCategory(defaultPIWebAPIUrl, defaultAssetServer, defaultName, defaultPassword, defaultAuthorization)
  expect_equal(statusCode, 201)
})

test_that("createTemplate", {
  statusCode <- createTemplate(defaultPIWebAPIUrl, defaultAssetServer, defaultPIServer, defaultName, defaultPassword, defaultAuthorization)
  expect_equal(statusCode, 201)
})

test_that("createElement", {
  statusCode <- createElement(defaultPIWebAPIUrl, defaultAssetServer, defaultName, defaultPassword, defaultAuthorization)
  expect_equal(statusCode, 200)
})

#Read/Write tests
test_that("doBatchCall", {
  statusCode <- doBatchCall(defaultPIWebAPIUrl, defaultAssetServer, defaultName, defaultPassword, defaultAuthorization)
  expect_equal(statusCode, 207)
})

test_that("readAttributeSelectedFields", {
  statusCode <- readAttributeSelectedFields(defaultPIWebAPIUrl, defaultAssetServer, defaultName, defaultPassword, defaultAuthorization)
  expect_equal(statusCode, 200)
})

test_that("readAttributeSnapshot", {
  statusCode <- readAttributeSnapshot(defaultPIWebAPIUrl, defaultAssetServer, defaultName, defaultPassword, defaultAuthorization)
  expect_equal(statusCode, 200)
})

test_that("readAttributeStream", {
  statusCode <- readAttributeStream(defaultPIWebAPIUrl, defaultAssetServer, defaultName, defaultPassword, defaultAuthorization)
  expect_equal(statusCode, 200)
})

test_that("writeDataSet", {
  statusCode <- writeDataSet(defaultPIWebAPIUrl, defaultAssetServer, defaultName, defaultPassword, defaultAuthorization)
  expect_equal(statusCode, 202)
})

test_that("writeSingleValue", {
  statusCode <- writeSingleValue(defaultPIWebAPIUrl, defaultAssetServer, defaultName, defaultPassword, defaultAuthorization)
  expect_equal(statusCode, 204)
})

test_that("updateAttributeValue", {
  statusCode <- updateAttributeValue(defaultPIWebAPIUrl, defaultAssetServer, defaultName, defaultPassword, defaultAuthorization)
  expect_equal(statusCode, 204)
})

#AF database deletion tests
test_that("deleteElement", {
  statusCode <- deleteElement(defaultPIWebAPIUrl, defaultAssetServer, defaultName, defaultPassword, defaultAuthorization)
  expect_equal(statusCode, 204)
})

test_that("deleteTemplate", {
  statusCode <- deleteTemplate(defaultPIWebAPIUrl, defaultAssetServer, defaultName, defaultPassword, defaultAuthorization)
  expect_equal(statusCode, 204)
})

test_that("deleteCategory", {
  statusCode <- deleteCategory(defaultPIWebAPIUrl, defaultAssetServer, defaultName, defaultPassword, defaultAuthorization)
  expect_equal(statusCode, 204)
})

test_that("deleteDatabase", {
  statusCode <- deleteDatabase(defaultPIWebAPIUrl, defaultAssetServer, defaultName, defaultPassword, defaultAuthorization)
  expect_equal(statusCode, 204)
})
