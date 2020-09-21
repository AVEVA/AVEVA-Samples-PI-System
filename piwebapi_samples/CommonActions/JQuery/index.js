/**
 * Set defaults on document ready
 */
$(document).ready(function() {
  $('#txtPIWebAPIUrl').val(testConfig.piWebApiUrl);
  $('#txtAssetServer').val(testConfig.assetServer);
  $('#txtPIServer').val(testConfig.piServer);

  $('#txtPIWebAPIUser').val(testConfig.userName);
  enableSubmit();
});

/**
 * Enable submit button if required fields have been provided
 */
function enableSubmit() {
  if (
    $('#txtPIWebAPIUrl').val() &&
    ($('#selAuthType option:selected').text() === 'Kerberos' ||
      ($('#txtPIWebAPIUser').val() && $('#txtPIWebAPIPassword').val())) &&
    $('#txtAssetServer').val() &&
    $('#txtPIServer').val()
  ) {
    $('#btnRunCode').attr('disabled', false);
  } else {
    $('#btnRunCode').attr('disabled', true);
  }
}

/**
 * Execute the code for the selected option
 */
function RunSelected() {
  if (!/^(http|https)?:\/\/[a-zA-Z0-9-.]/.test($('#txtPIWebAPIUrl').val())) {
    alert('Please enter a valid PI Web API URL');
    return;
  }

  var PIWebAPIUrl = $('#txtPIWebAPIUrl').val();
  var AssetServer = $('#txtAssetServer').val();
  var PIServer = $('#txtPIServer').val();
  var Name = $('#txtPIWebAPIUser').val();
  var Password = $('#txtPIWebAPIPassword').val();
  var AuthType = $('#selAuthType option:selected').text();

  switch ($('#selAction option:selected').text()) {
    case 'Write Single Value':
      writeSingleValue(PIWebAPIUrl, AssetServer, Name, Password, AuthType);
      break;
    case 'Write Set of Values':
      writeDataSet(PIWebAPIUrl, AssetServer, Name, Password, AuthType);
      break;
    case 'Update Attribute Value':
      updateAttributeValue(PIWebAPIUrl, AssetServer, Name, Password, AuthType);
      break;
    case 'Get Single Value':
      readAttributeSnapshot(PIWebAPIUrl, AssetServer, Name, Password, AuthType);
      break;
    case 'Get Set of Values':
      readAttributeStream(PIWebAPIUrl, AssetServer, Name, Password, AuthType);
      break;
    case 'Reduce Payload with Selected Fields':
      readAttributeSelectedFields(
        PIWebAPIUrl,
        AssetServer,
        Name,
        Password,
        AuthType
      );
      break;
    case 'Batch Writes and Reads':
      doBatchCall(PIWebAPIUrl, AssetServer, Name, Password, AuthType);
      break;
    case 'Create Database':
      createDatabase(PIWebAPIUrl, AssetServer, Name, Password, AuthType);
      break;
    case 'Create Template':
      createTemplate(
        PIWebAPIUrl,
        AssetServer,
        PIServer,
        Name,
        Password,
        AuthType
      );
      break;
    case 'Create Category':
      createCategory(PIWebAPIUrl, AssetServer, Name, Password, AuthType);
      break;
    case 'Create Element':
      createElement(PIWebAPIUrl, AssetServer, Name, Password, AuthType);
      break;
    case 'Delete Element':
      deleteElement(PIWebAPIUrl, AssetServer, Name, Password, AuthType);
      break;
    case 'Delete Template':
      deleteTemplate(PIWebAPIUrl, AssetServer, Name, Password, AuthType);
      break;
    case 'Delete Category':
      deleteCategory(PIWebAPIUrl, AssetServer, Name, Password, AuthType);
      break;
    case 'Delete Database':
      deleteDatabase(PIWebAPIUrl, AssetServer, Name, Password, AuthType);
      break;
  }
}
