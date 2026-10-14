"""Contract/fixture verification; actual generation is run by generate-piper-samples.py."""
import hashlib
import importlib.util
import json
import sys
import unittest
import wave
from pathlib import Path
sys.dont_write_bytecode=True
ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('pipeline',ROOT/'scripts/generate-piper-samples.py')
pipeline=importlib.util.module_from_spec(spec);spec.loader.exec_module(pipeline)
class PipelineTests(unittest.TestCase):
    def test_rejects_invalid_and_overlapping_cues(self):
        for cue in [{'start':-1,'end':1,'value':'D'},{'start':0,'end':float('nan'),'value':'D'},{'start':0,'end':2,'value':'D'},{'start':0,'end':1,'value':'manual'},{'start':True,'end':1,'value':'D'},{'start':0,'end':1,'value':None}]:
            with self.assertRaises(ValueError): pipeline.validate_cues({'mouthCues':[cue],'metadata':{'duration':1}},1)
        with self.assertRaises(ValueError): pipeline.validate_cues({'mouthCues':[{'start':0,'end':.8,'value':'D'},{'start':.5,'end':1,'value':'F'}],'metadata':{'duration':1}},1)
    def test_actual_outputs_have_matching_audio_and_raw_cues(self):
        for sample,(language,text,recognizer) in pipeline.SAMPLES.items():
            with self.subTest(sample=sample):
                manifest=json.loads((pipeline.OUTPUT/(sample+'.json')).read_text())
                wav=pipeline.OUTPUT/(sample+'.wav'); raw=pipeline.OUTPUT/(sample+'.cues.json')
                self.assertEqual(manifest['sha256'],hashlib.sha256(wav.read_bytes()).hexdigest())
                self.assertEqual(manifest['cueSha256'],hashlib.sha256(raw.read_bytes()).hexdigest())
                self.assertEqual(manifest['transcript'],text);self.assertEqual(manifest['language'],language)
                self.assertEqual(manifest['recognizer'],recognizer);self.assertEqual(manifest['kind'],'rhubarb')
                self.assertEqual(manifest['audioConversion'],'none')
                with wave.open(str(wav)) as audio:
                    self.assertEqual((audio.getnchannels(),audio.getsampwidth(),audio.getframerate()),(1,2,22050))
                    self.assertAlmostEqual(manifest['durationSeconds'],audio.getnframes()/audio.getframerate())
                cues=pipeline.validate_cues(json.loads(raw.read_text()),manifest['durationSeconds'])
                self.assertEqual(cues,manifest['mouthCues'])
                self.assertGreater(manifest['synthesisSeconds'],0);self.assertGreater(manifest['cueExtractionSeconds'],0)
if __name__=='__main__': unittest.main()
