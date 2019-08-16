"""This script will run all tests in order.
   Run the following command:
      python .\run_all_tests.py
"""

import unittest
import xmlrunner

class TestSequenceFunctions(unittest.TestCase):

    def test_a_createdatabase(self):
        from test_create_sandbox import TestStringMethods as SandboxMethods
        SandboxMethods.test_createdatabase(self)

    def test_b_createcategory(self):
        from test_create_sandbox import TestStringMethods as SandboxMethods
        SandboxMethods.test_createcategory(self)

    def test_c_createtemplate(self):
        from test_create_sandbox import TestStringMethods as SandboxMethods
        SandboxMethods.test_createtemplate(self)

    def test_d_createelement(self):
        from test_create_sandbox import TestStringMethods as SandboxMethods
        SandboxMethods.test_createelement(self)

    def test_e_writesinglevalue(self):
        from test_write_attributes import TestStringMethods as WriteMethods
        WriteMethods.test_writesinglevalue(self)

    def test_f_writedataset(self):
        from test_write_attributes import TestStringMethods as WriteMethods
        WriteMethods.test_writedataset(self)

    def test_g_updateattributevalue(self):
        from test_write_attributes import TestStringMethods as WriteMethods
        WriteMethods.test_updateattributevalue(self)

    def test_h_readattributesnapshot(self):
        from test_read_attributes import TestStringMethods as ReadMethods
        ReadMethods.test_readattributesnapshot(self)

    def test_i_readattributestream(self):
        from test_read_attributes import TestStringMethods as ReadMethods
        ReadMethods.test_readattributestream(self)

    def test_j_readattributeselectedfields(self):
        from test_read_attributes import TestStringMethods as ReadMethods
        ReadMethods.test_readattributeselectedfields(self)

    def test_k_dobatchcall(self):
        from test_batch_call import TestStringMethods as BatchMethods
        BatchMethods.test_dobatchcall(self)

    def test_l_deleteelement(self):
        from test_create_sandbox import TestStringMethods as SandboxMethods
        SandboxMethods.test_deleteelement(self)

    def test_m_deletetemplate(self):
        from test_create_sandbox import TestStringMethods as SandboxMethods
        SandboxMethods.test_deletetemplate(self)

    def test_n_deletecategory(self):
        from test_create_sandbox import TestStringMethods as SandboxMethods
        SandboxMethods.test_deletecategory(self)

    def test_o_delete_database(self):
        from test_create_sandbox import TestStringMethods as SandboxMethods
        SandboxMethods.test_deletedatabase(self)

if __name__ == '__main__':
    with open('output.xml', 'wb') as output:
        unittest.main(
            testRunner=xmlrunner.XMLTestRunner(output=output),
            failfast=False, buffer=False, catchbreak=False)
