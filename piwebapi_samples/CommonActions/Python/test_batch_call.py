""" This script contains the unit tests for the Batch Calls script """

import unittest

from test_config import PIWEBAPI_URL, AF_SERVER_NAME, USER_NAME, USER_PASSWORD, AUTH_TYPE


class TestStringMethods(unittest.TestCase):
    """
        We recommend running these unit tests using the
           file syntax:  python -m unittest test_batch_call
        To discover and run all unit tests:  python -m unittest
        To run the unit tests in a file:  python -m unittest test_batch_call
        To run a single test:  python -m unittest test_batch_call.TestStringMethods.test_dobatchcall
    """

    def test_dobatchcall(self):
        """ Call the do_batch_call method """
        from batch_call import do_batch_call
        self.assertEqual(do_batch_call(PIWEBAPI_URL, AF_SERVER_NAME,
                                       USER_NAME, USER_PASSWORD, AUTH_TYPE), 207)

if __name__ == '__main__':
    unittest.main()
