#!/usr/bin/env python3
"""SIMULATED verifier failures. No native input result is manufactured."""
import importlib.util,json,os,struct,sys,tempfile,unittest
from pathlib import Path
spec=importlib.util.spec_from_file_location('qualification',Path(__file__).with_name('run-native-qualification.py'))
module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
class Tests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory(prefix='paia-verifier-');self.root=Path(self.temp.name)
    def tearDown(self):self.temp.cleanup()
    def testAllRecordsAndOperationCountsAreRequired(self):
        path=self.root/'timings.bin';valid=b''.join(struct.pack('<QQQQ',i,100,20,10) for i in [1,2,3])
        path.write_bytes(valid);report={'operationSamples':3,'operationCounts':{'key':1,'selection':1,'clear':1}}
        self.assertEqual(module.summarize(path,report)['samples'],3)
        for broken in [valid[:-1],valid+struct.pack('<QQQQ',4,100,20,10),valid.replace(struct.pack('<QQQQ',1,100,20,10),struct.pack('<QQQQ',1,10,20,10))]:
            path.write_bytes(broken)
            with self.assertRaises(RuntimeError):module.summarize(path,report)
        path.write_bytes(valid)
        with self.assertRaises(RuntimeError):module.summarize(path,report|{'operationSamples':4})
        with self.assertRaises(RuntimeError):module.summarize(path,report|{'operationCounts':{'key':2,'selection':0,'clear':1}})
    def testSupervisorReapsTimeoutAndPreservesIncompleteReceipt(self):
        path=self.root/'hang.log'
        with self.assertRaises(RuntimeError):module.run([sys.executable,'-c','import time;time.sleep(30)'],path,.1,os.environ.copy())
        receipt=json.loads(path.with_suffix('.process.json').read_text())
        self.assertTrue(receipt['timeout']);self.assertNotEqual(receipt['exitCode'],0)
    def testInventoriesRejectLinksAndNoticeByteChanges(self):
        p=self.root/'authored';p.write_text('authored');before=module.inventory(self.root)
        p.write_text('changed');self.assertNotEqual(before,module.inventory(self.root))
        (self.root/'link').symlink_to(p)
        with self.assertRaises(RuntimeError):module.inventory(self.root)
    def testHostSuccessRequiresActualUniqueCompleteReceipt(self):
        text="APPKIT_HOST qualification episodes=32 insertCalls=128; real production controller and NSTextView-backed authored IMK client; installed=false"
        self.assertEqual(module.host_receipt(text)["insertCalls"],128)
        for invalid in ["",text+"\n"+text,text.replace("episodes=32","episodes=31"),text.replace("insertCalls=128","insertCalls=0")]:
            with self.assertRaises(RuntimeError):module.host_receipt(invalid)
    def testFullGateCannotBeReplacedByCalibration(self):
        self.assertEqual(module.MINIMUM,1_000_000);self.assertEqual(module.CALIBRATION,10_000)
if __name__=='__main__':unittest.main()
