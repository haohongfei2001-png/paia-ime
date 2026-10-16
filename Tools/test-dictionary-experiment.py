#!/usr/bin/env python3
import gzip,unittest
import dictionary_experiment as d
class Tests(unittest.TestCase):
 def testExactHistoricalSnapshotAndDictionary(self):
  lock,data,dictionary,report=d.verify()
  self.assertEqual(lock['snapshot']['sha256'],lock['historicalSnapshot']['sha256'])
  self.assertEqual(report['sourceRows'],78478);self.assertEqual(report['uniqueCharacterReadings'],52691)
  self.assertEqual(len(report['unsupported']),8)
  self.assertEqual(d.pack(data),d.pack(data));self.assertEqual(gzip.decompress(d.pack(data)),data)
 def testToneAndUmlaut(self):
  for raw,want in [('lǜ','lv'),('nǐ','ni'),('ḿ','m'),('ǹ','n'),('lü','lv')]:self.assertEqual(d.spelling(raw),want)
  for raw in ['ê','ề','xi an','ni3','a\n','']: 
   with self.assertRaises(ValueError):d.spelling(raw)
 def testAllReadingsAndUniformWeight(self):
  text='1\tU+4E00\tkMandarin\tyī yí\n2\tU+4E00\tkHanyuPinyin\t10000.010:yī,yǐ\n'
  data,report=d.convert(text.encode());self.assertEqual(report['uniqueCharacterReadings'],1)
  self.assertIn('一\tyi\t1\n',data.decode())
 def testRejectMalformedInput(self):
  for text in ['','1\tU+4E00\tkUnknown\tyī\n','1\tU+110000\tkMandarin\tyī\n','1\tU+D800\tkMandarin\tyī\n','1\tU+4E00\tkHanyuPinyin\tbad:yī\n','1\tU+4E00\tkMandarin\tyī\n1\tU+4E01\tkMandarin\tdīng\n']:
   with self.assertRaises(ValueError):d.convert(text.encode())
 def testChangedSourceIsRefused(self):
  with self.assertRaises(ValueError):d.checked(b'changed',{'bytes':7,'sha256':'0'*64})
  with self.assertRaises(ValueError):d.snapshot(b'# Unicode Version 16.0.0\nU+4E00\tkMandarin\tyi\n')
if __name__=='__main__':unittest.main()
