"""Exercise public-package safety with disposable source/dependency fixtures."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import zipfile

spec=importlib.util.spec_from_file_location('packager',Path(__file__).resolve().parents[1]/'scripts/package-movement.py')
p=importlib.util.module_from_spec(spec)
spec.loader.exec_module(p)


class Packaging(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory()
        self.root=Path(self.temp.name).resolve()
        self.bundle=self.root/'bundle'
        self.build=self.root/'build'
        self.output=self.root/'out'
        self.patch=patch.object(p,'ROOT',self.root)
        self.patch.start()
        self.git=patch.object(p,'git',side_effect=lambda *a: '' if a[0]=='status' else 'a'*40)
        self.git.start()
        self.put('bundle/game-root/runtime.dll',b'dependency')
        lock={'source_release':'https://example.invalid/release','runtime_versions':{},
              'files':[{'path':'game-root/runtime.dll','sha256':p.sha(b'dependency'),'bytes':10}]}
        self.put('scripts/movement-dependencies.json',json.dumps(lock).encode())
        self.put('build/CMakeCache.txt',f'COOP_LEGACY_PLUGIN:BOOL=OFF\nCMAKE_HOME_DIRECTORY:INTERNAL={self.root}\n'.encode())
        self.put('build/CoopPlugin/Release/CP2077Coop.dll',b'typed-test')
        self.put('runtime/session/cet/CP2077Coop/config.lua',b'return { experimentalPlayerMovement = false }')
        self.put('runtime/session/diagnostics/CP2077MovementDiagnostics/init.lua',b'-- diagnostic')
        self.put('runtime/session/redscript/CP2077Coop/natives.reds',b'// typed')
        self.put('docs/MOVEMENT_TEST_PACKAGE.md',b'instructions')
        self.put('scripts/collect-movement-logs.ps1',b'# collector')

    def tearDown(self):
        self.git.stop(); self.patch.stop(); self.temp.cleanup()

    def put(self,path,data):
        target=self.root/path; target.parent.mkdir(parents=True,exist_ok=True); target.write_bytes(data)

    def test_role_archives_and_checksums(self):
        # Files outside the pinned allowlist must not enter a distributable.
        self.put('bundle/game-root/access.key',b'private')
        self.put('bundle/game-root/old-relay.dll',b'old')
        p.package(self.bundle,self.build,self.output,'v0.1.0-movement-experiment.1')
        games=[]
        for role in ('HOST','JOINER'):
            with zipfile.ZipFile(next(self.output.glob(f'*-{role}.zip'))) as z:
                games.append({n:z.read(n) for n in z.namelist() if n.startswith('game-root/')})
                self.assertIn(f'role={role}',z.read('config-examples/session.ini.example').decode())
                self.assertNotIn('game-root/access.key',z.namelist())
                self.assertNotIn('game-root/old-relay.dll',z.namelist())
                self.assertIn(b'experimentalPlayerMovement = true',games[-1]['game-root/bin/x64/plugins/cyber_engine_tweaks/mods/CP2077Coop/config.lua'])
                manifest=json.loads(z.read('package-manifest.json'))
                for f in manifest['files']:
                    self.assertEqual(p.sha(z.read(f['path'])),f['sha256'])
        self.assertEqual(games[0],games[1])
        with self.assertRaisesRegex(ValueError,'output must not exist'):
            p.package(self.bundle,self.build,self.output,'v0.1.0-movement-experiment.1')

    def test_rejects_corrupt_dependency_before_writing(self):
        self.put('bundle/game-root/runtime.dll',b'corrupt')
        with self.assertRaisesRegex(ValueError,'dependency mismatch'):
            p.package(self.bundle,self.build,self.output,'v0.1.0-movement-experiment.1')
        self.assertFalse(self.output.exists())

    def test_rejects_legacy_build(self):
        self.put('build/CMakeCache.txt',b'COOP_LEGACY_PLUGIN:BOOL=ON')
        with self.assertRaisesRegex(ValueError,'typed Release'):
            p.package(self.bundle,self.build,self.output,'v0.1.0-movement-experiment.1')

    def test_rejects_other_checkout_build(self):
        self.put('build/CMakeCache.txt',b'COOP_LEGACY_PLUGIN:BOOL=OFF\nCMAKE_HOME_DIRECTORY:INTERNAL=/wrong/source\n')
        with self.assertRaisesRegex(ValueError,'another checkout'):
            p.package(self.bundle,self.build,self.output,'v0.1.0-movement-experiment.1')

    def test_rejects_dirty_source(self):
        with patch.object(p,'git',return_value=' M runtime.lua'):
            with self.assertRaisesRegex(ValueError,'commit exact source'):
                p.package(self.bundle,self.build,self.output,'v0.1.0-movement-experiment.1')


if __name__=='__main__':
    unittest.main()
