"""Resolve only SHA-256 pinned public build dependencies; never school sessions."""
import hashlib,json
from pathlib import Path
from urllib.request import urlopen

ROOT=Path(__file__).resolve().parents[1]

def dependencies(download=False):
    lock=json.loads((ROOT/'dependencies.lock.json').read_text(encoding='utf-8'))
    folder=ROOT/'build'/'deps';folder.mkdir(parents=True,exist_ok=True)
    result=[]
    for item in lock['artifacts']:
        path=folder/Path(item['path']).name
        if not path.exists():
            if not download:raise SystemExit('Missing pinned XLS dependencies; run python scripts/dependencies.py first.')
            with urlopen(lock['repository']+item['path'],timeout=60) as response:data=response.read(20*1024*1024+1)
            if len(data)>20*1024*1024:raise SystemExit('Dependency too large')
            if hashlib.sha256(data).hexdigest()!=item['sha256']:raise SystemExit('Dependency checksum mismatch')
            path.write_bytes(data)
        if hashlib.sha256(path.read_bytes()).hexdigest()!=item['sha256']:raise SystemExit('Dependency checksum mismatch: '+path.name)
        result.append(path)
    return result

if __name__=='__main__':
    print('Verified',len(dependencies(download=True)),'pinned public dependencies.')
