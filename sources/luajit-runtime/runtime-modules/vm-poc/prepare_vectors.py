"""Regenerate current-build vector witnesses without changing live receipts."""
from pathlib import Path
import hashlib,json

ROOT=Path(__file__).resolve().parent

def prepare():
    work=ROOT/'work';work.mkdir(exist_ok=True)
    counts={}
    for family in ('vector2','vector3','vector3box','vector4'):
        evidence=json.loads((ROOT/(family+'-binding-evidence.json')).read_text())
        image=Path(evidence['capture']).read_bytes()
        assert hashlib.sha256(image).hexdigest()==evidence['capture_sha256']
        lines=[]
        for name,row in evidence['regions'].items():
            data=image[int(row['entry'],16):int(row['end'],16)]
            assert hashlib.sha256(data).hexdigest()==row['sha256'],name
            lines.append('static const unsigned char '+name+'[]={'+','.join(map(str,data))+'};')
        (work/(family+'_witnesses.h')).write_text('\n'.join(lines)+'\n')
        counts[family]=len(lines)
    print(json.dumps(counts))

if __name__=='__main__':prepare()
