using System;
using System.Collections.Generic;
using System.Data;
using System.Data.OleDb;
using System.Linq;
using Xunit;
using Xunit.Abstractions;

namespace OSIsoft.PISystemDeploymentTests
{
    /// <summary>
    /// Test class containing tests dedicated for PI SQL Client and PI SQL Data Access Server (RTQP Engine).
    /// </summary>
    [Collection("AF collection")]
    public class PISqlClientTests : IClassFixture<AFFixture>
    {
        internal const string KeySetting = "PISqlClientTests";
        internal const TypeCode KeySettingTypeCode = TypeCode.Boolean;

        private readonly string _provider = "PISQLClient.1";
        private readonly string _integratedSecurity = "SSPI";
        private readonly string _connectionString;

        /// <summary>
        /// Initializes a new PiSqlClientTests object.
        /// </summary>
        /// <param name="output">The output logger used for writing messages.</param>
        public PISqlClientTests(ITestOutputHelper output)
        {
            Output = output;
            _connectionString = $"Provider={_provider};Data Source={Settings.AFDatabase};Location={Settings.AFServer};Integrated Security={_integratedSecurity}";
        }

        private ITestOutputHelper Output { get; }

        /// <summary>
        /// Executes basic Master.Element.Element table queries against the PI SQL Data Access Server (RTQP Engine)
        /// using the PI SQL Client OLEDB provider.
        /// </summary>
        /// <remarks>
        /// Test Steps:
        /// <para>Try to Connect to AF Server using specified connection string</para>
        /// <para>Execute the given query</para>
        /// <para>Check that number of rows returned by query equal the expected amount</para>
        /// </remarks>
        /// <param name="query">Query to execute.</param>
        [OptionalTheory(KeySetting, KeySettingTypeCode)]
        [InlineData("SELECT * FROM Master.Element.Element")]
        [InlineData("SELECT Template, Name FROM Master.Element.Element")]
        [InlineData("SELECT Template, PrimaryPath + Name FROM Master.Element.Element ORDER BY Template, PrimaryPath")]
        public void ElementQueryTest(string query)
        {
            using (var oleDbConnection = new OleDbConnection(_connectionString))
            using (var oleDbCommand = new OleDbCommand(query, oleDbConnection))
            {
                Output.WriteLine($"Attempting to connect to AF Server using connectionString [{_connectionString}].");
                oleDbConnection.Open();

                Output.WriteLine($"Executing query [{query}].");
                using (var reader = oleDbCommand.ExecuteReader())
                {
                    Assert.True(reader.HasRows, $"The following SQL command did not return any rows: [{query}].");

                    var actualElementCount = 0;

                    while (reader.Read())
                        actualElementCount++;
                    Output.WriteLine($"Check if Number of rows returned equals total number of rows.");
                    Assert.True(AFFixture.TotalElementCount.Equals(actualElementCount), $"Query returned {actualElementCount} rows but expected {AFFixture.TotalElementCount}.");
                }
            }
        }

        /// <summary>
        /// Executes basic Master.Element.FindElements table-valued function queries against the PI SQL Data Access Server (RTQP Engine)
        /// using the PI SQL Client OLEDB provider.
        /// </summary>
        /// <remarks>
        /// Test Steps:
        /// <para>Make sure number of rows returned by query equals the expected number</para>
        /// </remarks>
        /// <param name="query">Query to execute.</param>
        /// <param name="expectedRowCount">Number of expected result rows.</param>
        [OptionalTheory(KeySetting, KeySettingTypeCode)]
        [InlineData("SELECT * FROM [Master].[Element].[FindElements]('Name:=*')", AFFixture.TotalElementCount)]
        [InlineData("SELECT * FROM [Master].[Element].[FindElements]('Name:=Region*')", AFFixture.TotalRegionCount)]
        [InlineData("SELECT * FROM [Master].[Element].[FindElements]('Name:=\"Wind Farm*\"')", AFFixture.TotalWindFarmCount)]
        [InlineData("SELECT * FROM [Master].[Element].[FindElements]('Name:=TUR*')", AFFixture.TotalTurbineCount)]
        [InlineData("SELECT * FROM [Master].[Element].[FindElements]('Template:=Turbine')", AFFixture.TotalTurbineCount)]
        public void FindElementQueryTest(string query, int expectedRowCount)
        {
            using (var result = ExecuteQuery(query))
            {
                Assert.True(expectedRowCount.Equals(result.Rows.Count),
                    $"Query expected to return {expectedRowCount} but returned {result.Rows.Count}.");
            }
        }

        /// <summary>
        /// Executes basic Master.Element.Attribute table queries against the PI SQL Data Access Server (RTQP Engine)
        /// using the PI SQL Client OLEDB provider.
        /// </summary>
        /// <remarks>
        /// Test Steps:
        /// <para>Attempt to connect to AF server using Connection String</para>
        /// <para>Run given Sql Query</para>
        /// <para>Check to make sure Query contained correct number of attributes</para>
        /// </remarks>
        /// <param name="query">Query to execute.</param>
        [OptionalTheory(KeySetting, KeySettingTypeCode)]
        [InlineData("SELECT * FROM Master.Element.Attribute")]
        [InlineData("SELECT Element, Name FROM Master.Element.Attribute")]
        [InlineData("SELECT Element, Name, Value, UnitOfMeasure, DataReference FROM Master.Element.Attribute ORDER BY Element, Name")]
        public void ElementAttributeQueryTest(string query)
        {
            using (var oleDbConnection = new OleDbConnection(_connectionString))
            using (var oleDbCommand = new OleDbCommand(query, oleDbConnection))
            {
                oleDbCommand.CommandTimeout = 120;
                Output.WriteLine($"Attempting to connect to AF Server using [{_connectionString}].");
                oleDbConnection.Open();

                Output.WriteLine($"Executing query [{query}].");
                using (var reader = oleDbCommand.ExecuteReader())
                {
                    Assert.True(reader.HasRows, $"The following SQL command did not return any rows: [{query}].");
                    var elements = new List<string>();
                    string currentElement = null;

                    while (reader.Read())
                    {
                        currentElement = reader["Element"].ToString();

                        if (elements.Contains(currentElement))
                            continue;

                        elements.Add(currentElement);
                    }

                    Output.WriteLine($"Check returned elements with expected elements.");
                    int count = elements.Count(element => element.StartsWith("Region", StringComparison.OrdinalIgnoreCase));
                    Assert.True(AFFixture.TotalRegionCount.Equals(count),
                        $"Expected {AFFixture.TotalRegionCount} elements starting with 'Region' but found {count}.");

                    count = elements.Count(element => element.StartsWith("Wind Farm", StringComparison.OrdinalIgnoreCase));
                    Assert.True(AFFixture.TotalWindFarmCount.Equals(count),
                        $"Expected {AFFixture.TotalWindFarmCount} elements starting with 'Wind Farm' but found {count}.");

                    count = elements.Count(element => element.StartsWith("TUR", StringComparison.OrdinalIgnoreCase));
                    Assert.True(AFFixture.TotalTurbineCount.Equals(count),
                        $"Expected {AFFixture.TotalTurbineCount} elements starting with 'TUR' but found {count}.");

                    count = elements.Count;
                    Assert.True(AFFixture.TotalElementCount.Equals(count),
                        $"Expected {AFFixture.TotalElementCount} total elements, but found {count}.");
                }
            }
        }

        /// <summary>
        /// Executes basic Master.Element.Archive table queries against the PI SQL Data Access Server (RTQP Engine)
        /// using the PI SQL Client OLEDB provider.
        /// </summary>
        /// <remarks>
        /// Test Steps:
        /// <para>Run Given Query</para>
        /// <para>Check that number of columns and rows returned equals the expected count</para>
        /// <para>Check to make sure data returned is good</para>
        /// </remarks>
        /// <param name="query">Query to execute.</param>
        [OptionalTheory(KeySetting, KeySettingTypeCode)]
        [InlineData(@"SELECT TOP 100 eh.Path, eh.Name Element, ea.Name Attribute, a.Value, a.Value_Int, a.Value_Double, a.Value_String, a.Value_DateTime, 
	                  a.IsValueAnnotated, a.IsValueGood, a.IsValueQuestionable, a.IsValueSubstituted, a.Error
                      FROM
                      (
	                      SELECT TOP 5 Path, Name, ElementID
	                      FROM [Master].[Element].[ElementHierarchy]
	                      WHERE Level = 2
	                      ORDER BY Path, Name
                      ) eh
                      INNER JOIN [Master].[Element].[Attribute] ea ON ea.ElementID = eh.ElementID
                      INNER JOIN [Master].[Element].[Archive] a ON a.AttributeID = ea.ID
                      WHERE (a.TimeStamp BETWEEN '*-12h' AND '*') AND (ea.Name LIKE '%SineWave%')
                      ORDER BY eh.Path, eh.Name, ea.Name")]
        public void ArchiveQueryTest(string query)
        {
            Output.WriteLine($"Executing query [{query}].");
            using (var result = ExecuteQuery(query))
            {
                Output.WriteLine($"Checking Rows and Columns are equal.");
                Assert.True(
                    result.Columns.Count == 13,
                    $"Expected 13 columns from the following SQL command but {result.Columns.Count} were retrieved from query [{query}].");
                Assert.True(
                    result.Rows.Count == 100,
                    $"Expected 100 rows from the following SQL command but {result.Rows.Count} were retrieved from query [{query}].");

                Output.WriteLine($"Checking Data returned by query.");
                foreach (DataRow row in result.Rows)
                {
                    string actualErrorValue = row.ItemArray[result.Columns["Error"].Ordinal].ToString();
                    Assert.True(string.IsNullOrEmpty(actualErrorValue), $"Expected the Error column for row {row[0]} to be empty but the actual value was [{actualErrorValue}].");

                    Assert.True(bool.Parse(row.ItemArray[result.Columns["IsValueGood"].Ordinal].ToString()), $"Expected the IsValueGood value for row {row[0]} to be true but it was not.");
                }
            }
        }

        /// <summary>
        /// Executes basic Master.Element.GetSummary table-valued function queries against the PI SQL Data Access Server (RTQP Engine)
        /// using the PI SQL Client OLEDB provider.
        /// </summary>
        /// <remarks>
        /// Test Steps:
        /// <para>Run queries from inline data</para>
        /// <para>Check rows to make sure number of returned rows matches expected number of rows</para>
        /// </remarks>
        /// <param name="query">Query to execute.</param>
        /// <param name="expectedRowCount">Expected number of rows to be retrieved from the query result.</param>
        [OptionalTheory(KeySetting, KeySettingTypeCode)]
        [InlineData(@"SELECT * FROM [Master].[Element].[Element] e
                     INNER JOIN [Master].[Element].[Attribute] ea ON ea.ElementID = e.ID
                     CROSS APPLY[Master].[Element].[GetSummary] (ea.ID, 'y', 't', 'Average', 'TimeWeighted', 'MostRecentTime' ) s
                     WHERE e.Template = 'Turbine' AND ea.Path = '|Analog|' AND ValueType = 'Double'", AFFixture.TotalTurbineCount * 2)]
        public void SummaryQueryTest(string query, int expectedRowCount)
        {
            Output.WriteLine($"Checking that expected row count is equal to the row count returned by query [{query}].");
            using (var result = ExecuteQuery(query))
            {
                Assert.True(expectedRowCount.Equals(result.Rows.Count),
                    $"Expected {expectedRowCount} rows but query returned {result.Rows.Count}.");
            }
        }

        /// <summary>
        /// Executes basic Master.Element.GetSampledValue table-valued function queries against the PI SQL Data Access Server (RTQP Engine)
        /// using the PI SQL Client OLEDB provider.
        /// </summary>
        /// <remarks>
        /// Test Steps:
        /// <para>Run queries from inline data</para>
        /// <para>Check rows to make sure number of returned rows matches expected number of rows</para>
        /// </remarks>
        /// <param name="query">Query to execute.</param>
        /// <param name="expectedRowCount">Expected number of rows to be retrieved from the query result.</param>
        [OptionalTheory(KeySetting, KeySettingTypeCode)]
        [InlineData(@"SELECT * FROM [Master].[Element].[Element] e
                     INNER JOIN [Master].[Element].[Attribute] ea ON ea.ElementID = e.ID
                     CROSS APPLY[Master].[Element].[GetSampledValue] (ea.ID, N't') s
                     WHERE e.Template = 'Turbine' AND ea.Path = '|Analog|' AND ValueType = 'Double'", AFFixture.TotalTurbineCount * 2)]
        public void SampledValueQueryTest(string query, int expectedRowCount)
        {
            Output.WriteLine($"Checking that expected row count is equal to the row count returned by query [{query}].");
            using (var result = ExecuteQuery(query))
            {
                Assert.True(expectedRowCount.Equals(result.Rows.Count),
                    $"Expected {expectedRowCount} rows but query returned {result.Rows.Count}.");
            }
        }

        /// <summary>
        /// Executes basic Data Definition Language queries against the PI SQL Data Access Server (RTQP Engine)
        /// using the PI SQL Client OLEDB provider.
        /// </summary>
        /// <remarks>
        /// Test Steps:
        /// <para>Run set of queries</para>
        /// <para>Make sure that the affected rows is equal to -1</para>
        /// </remarks>
        [OptionalFact(KeySetting, KeySettingTypeCode)]
        public void CreateAlterAndDropFunctionTest()
        {
            try
            {
                Output.WriteLine($"Run set queries and check affected rows.");
                var affectedRows = ExecuteNonQuery("CREATE Catalog CustomCatalog");
                Assert.True((-1).Equals(affectedRows), $"Query [CREATE Catalog CustomCatalog] returned {affectedRows} instead of -1.");
                affectedRows = ExecuteNonQuery("CREATE Schema CustomCatalog.CustomSchema");
                Assert.True((-1).Equals(affectedRows), $"Query [CREATE Schema CustomCatalog.CustomSchema] returned" +
                    $" {affectedRows} instead of -1.");

                affectedRows = ExecuteNonQuery("CREATE Function CustomCatalog.CustomSchema.TestFunction(@param1 String)" +
                    " AS SELECT 'Test' test WHERE @param1 = 'TestParam1'");

                Assert.True((-1).Equals(affectedRows), $"Query [CREATE Function CustomCatalog.CustomSchema.TestFunction(@param1 String)" +
                    $" AS SELECT 'Test' test WHERE @param1 = 'TestParam1'] returned {affectedRows} instead of -1.");

                using (var result = ExecuteQuery("SELECT * FROM CustomCatalog.CustomSchema.TestFunction('TestParam1')"))
                {
                    affectedRows = ExecuteNonQuery("ALTER Function CustomCatalog.CustomSchema.TestFunction(@param2 String)" +
                        " AS SELECT 'Test2' test2 WHERE @param2 = 'TestParam2'");

                    Assert.True((-1).Equals(affectedRows), $"Query [ALTER Function CustomCatalog.CustomSchema.TestFunction(@param2 String)" +
                        $" AS SELECT 'Test2' test2 WHERE @param2 = 'TestParam2'] returned {affectedRows} instead of -1.");
                }

                using (var result = ExecuteQuery("SELECT * FROM CustomCatalog.CustomSchema.TestFunction('TestParam2')"))
                {
                    Assert.True(result.Rows.Count.Equals(1), $"Query [SELECT * FROM CustomCatalog.CustomSchema.TestFunction('TestParam2')]" +
                        $" returns {result.Rows.Count} rows instead of 1.");

                    Assert.True(result.Columns.Count.Equals(1), $"Query [SELECT * FROM CustomCatalog.CustomSchema.TestFunction('TestParam2')]" +
                        $" returns {result.Columns.Count} columns instead of 1.");
                }

                affectedRows = ExecuteNonQuery("DROP Function CustomCatalog.CustomSchema.TestFunction");
                Assert.True((-1).Equals(affectedRows), $"Query [DROP Function CustomCatalog.CustomSchema.TestFunction] returned" +
                    $" {affectedRows} instead of -1.");

                affectedRows = ExecuteNonQuery("DROP Schema CustomCatalog.CustomSchema");
                Assert.True((-1).Equals(affectedRows), $"Query [DROP Schema CustomCatalog.CustomSchema] returned {affectedRows} instead of -1.");
            }
            finally
            {
                var affectedRows = ExecuteNonQuery("DROP Catalog CustomCatalog");
                Assert.True((-1).Equals(affectedRows), $"Query [DROP Catalog CustomCatalog] returned {affectedRows} instead of -1.");
            }
        }

        /// <summary>
        /// Helper method used to execute queries.
        /// </summary>
        /// <param name="query">Query to execute.</param>
        /// <returns>Result table.</returns>
        private DataTable ExecuteQuery(string query)
        {
            using (var oleDbConnection = new OleDbConnection(_connectionString))
            using (var oleDbCommand = new OleDbCommand(query, oleDbConnection))
            {
                Output.WriteLine($"Attempting to connect to AF Server using connectionString [{_connectionString}].");
                oleDbConnection.Open();

                Output.WriteLine($"Executing query [{query}].");
                using (var dataAdapter = new OleDbDataAdapter(oleDbCommand))
                {
                    var dataTable = new DataTable("QueryResult");
                    dataAdapter.Fill(dataTable);
                    Output.WriteLine("Query executed successfully.");

                    return dataTable;
                }
            }
        }

        /// <summary>
        /// Helper method used to execute queries which do not return result data.
        /// </summary>
        /// <param name="query">Query to execute.</param>
        /// <returns>Number of affected rows.</returns>
        private int ExecuteNonQuery(string query)
        {
            using (var oleDbConnection = new OleDbConnection(_connectionString))
            using (var oleDbCommand = new OleDbCommand(query, oleDbConnection))
            {
                Output.WriteLine($"Attempting to connect to AF Server using connectionString [{_connectionString}].");
                oleDbConnection.Open();

                Output.WriteLine($"Executing query [{query}].");
                var affectedRows = oleDbCommand.ExecuteNonQuery();
                Output.WriteLine("Query executed successfully.");

                return affectedRows;
            }
        }
    }
}
