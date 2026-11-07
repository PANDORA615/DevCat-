import unittest
from publish_prerelease import source_packages, validate_proof, LANGUAGES


class PrereleaseValidation(unittest.TestCase):
    def proof(self):
        return {'schema':1, 'platform':'windows', 'commit':'candidate-merge',
                'packagedRuntimeCheck':{'passed':True, 'languages':{k:{'passed':True} for k in LANGUAGES}},
                'files':[{'name':name,'bytes':10,'sha256':'a'*64} for name in
                         ['DevCat-0.9.2-windows-x64.zip','DevCat-0.9.2-windows-x64-setup.exe']]}

    def test_proof_requires_the_tested_tree_and_every_language(self):
        validate_proof(self.proof(),'windows',lambda _: 'tested-tree','tested-tree')
        with self.assertRaises(AssertionError):
            validate_proof(self.proof(),'windows',lambda _: 'other-tree','tested-tree')
        broken=self.proof();broken['packagedRuntimeCheck']['languages']['go']['passed']=False
        with self.assertRaises(AssertionError):
            validate_proof(broken,'windows',lambda _: 'tested-tree','tested-tree')

    def test_package_names_sizes_and_hashes_cannot_be_unchecked(self):
        for field,value in [('name','../elsewhere'),('bytes',2*1024**3),('sha256','')]:
            proof=self.proof();proof['files'][0][field]=value
            with self.assertRaises(AssertionError):
                validate_proof(proof,'windows',lambda _: 'tested-tree','tested-tree')

    def test_corresponding_source_versions_ignore_binary_rebuild_suffixes(self):
        inventories=[{'packages':[
            {'metadata':'Package: example-bin\nVersion: 1.2+b4\nSource: example (1.2)\n'},
            {'metadata':'Package: simple\nVersion: 3.0+b1\n'}]}]
        self.assertEqual(source_packages(inventories), {('example','1.2'),('simple','3.0')})


if __name__=='__main__':unittest.main()
