""" This script contains the unit tests for the CreateSandbox Script """

import unittest

from test_config import PIWEBAPI_URL, AF_SERVER_NAME, PI_SERVER_NAME, USER_NAME, USER_PASSWORD, AUTH_TYPE


class TestStringMethods(unittest.TestCase):
    """
        Run each unit tests in order, manually using the following example:
            python -m unittest test_create_sandbox.TestStringMethods.test_createdatabase
        To discover and run all unit tests:  python -m unittest
        To run the unit tests in a file:  python -m unittest test_create_sandbox
        To run a single test:
            python -m unittest test_create_sandbox.TestStringMethods.test_createdatabase
    """

    def test_createdatabase(self):
        """ Test the create_database method """
        from create_sandbox import create_database
        self.assertEqual(create_database(PIWEBAPI_URL,
                                         AF_SERVER_NAME, USER_NAME, USER_PASSWORD, AUTH_TYPE), 201)

    def test_createcategory(self):
        """ Test the create_category method """
        from create_sandbox import create_category
        self.assertEqual(create_category(PIWEBAPI_URL,
                                         AF_SERVER_NAME, USER_NAME, USER_PASSWORD, AUTH_TYPE), 201)

    def test_createtemplate(self):
        """ Test the create_template method """
        from create_sandbox import create_template
        self.assertEqual(create_template(PIWEBAPI_URL,
                                         AF_SERVER_NAME, PI_SERVER_NAME, USER_NAME, USER_PASSWORD, AUTH_TYPE), 201)

    def test_createelement(self):
        """ Test the create_element method """
        from create_sandbox import create_element
        self.assertEqual(create_element(PIWEBAPI_URL,
                                        AF_SERVER_NAME, USER_NAME, USER_PASSWORD, AUTH_TYPE), 200)

    def test_deleteelement(self):
        """ Test the delete_element method """
        from create_sandbox import delete_element
        self.assertEqual(delete_element(PIWEBAPI_URL,
                                        AF_SERVER_NAME, USER_NAME, USER_PASSWORD, AUTH_TYPE), 204)

    def test_deletetemplate(self):
        """ Test the delete_template method """
        from create_sandbox import delete_template
        self.assertEqual(delete_template(PIWEBAPI_URL,
                                         AF_SERVER_NAME, USER_NAME, USER_PASSWORD, AUTH_TYPE), 204)

    def test_deletecategory(self):
        """ Test the delete_category method """
        from create_sandbox import delete_category
        self.assertEqual(delete_category(PIWEBAPI_URL,
                                         AF_SERVER_NAME, USER_NAME, USER_PASSWORD, AUTH_TYPE), 204)

    def test_deletedatabase(self):
        """ Test the create_database method """
        from create_sandbox import delete_database
        self.assertEqual(delete_database(PIWEBAPI_URL,
                                         AF_SERVER_NAME, USER_NAME, USER_PASSWORD, AUTH_TYPE), 204)


if __name__ == '__main__':
    unittest.main()
