"""Deterministic public snapshot; no credentials or build artifacts are copied."""
from pathlib import Path, PurePosixPath
import hashlib,json,os,posixpath,stat,subprocess,sys,tarfile
BUILDER_SHA='636decefd426586118c0a06de03d2d3c2cc24cde'
UPSTREAM='24638bc69bd083981b178dd1e7f921eebbf7fc46'
def sha(path):
    h=hashlib.sha256()
    with open(path,'rb') as f:
        for b in iter(lambda:f.read(1024*1024),b''): h.update(b)
    return h.hexdigest()
def snapshot(builder,source,out):
    builder,source,out=map(lambda p:Path(p).resolve(),(builder,source,out));out.mkdir(parents=True,exist_ok=True)
    sys.path.insert(0,str(builder/'scripts'))
    from jg132_post181 import verify_source
    verify_source(source)
    status=subprocess.check_output(['git','submodule','status','--recursive'],cwd=source,text=True)
    assert status and all(line.startswith(' ') for line in status.splitlines()),'Uninitialized/mismatched dependency'
    import prepare_jg13_build_rules as rules
    rules.SOURCE=source/'build-system/bazel-rules/rules_apple'; rules.main()
    excluded={'.git','build-input','bazel-bin','bazel-out','bazel-testlogs','bazel-swiftgram-src','bazel-source','__pycache__'}
    paths=[]
    for directory,dirs,files in os.walk(source,followlinks=False):
        rel=Path(directory).relative_to(source)
        dirs[:]=sorted(d for d in dirs if d not in excluded and not (str(rel)=='.github' and d=='workflows'))
        for d in dirs[:]:
            p=Path(directory)/d
            if p.is_symlink(): paths.append(p); dirs.remove(d)
        paths.extend(Path(directory)/f for f in files if f not in {'.git','.DS_Store'} and not f.endswith('.pyc'))
    files=[];tarpath=out/'source.tar';prefix='Jerkgram-1.2.0-source'
    with tarfile.open(tarpath,'w',format=tarfile.PAX_FORMAT) as tf:
        for p in sorted(paths,key=lambda p:p.relative_to(source).as_posix()):
            rel=p.relative_to(source).as_posix();parts=PurePosixPath(rel).parts
            assert '.git' not in parts and not rel.startswith('.github/workflows/')
            assert not rel.startswith('build-input/')
            info=tf.gettarinfo(str(p),arcname=prefix+'/'+rel)
            info.uid=info.gid=0;info.uname=info.gname='';info.mtime=0;info.pax_headers={}
            info.mode=0o777 if info.issym() else (0o755 if p.stat().st_mode & stat.S_IXUSR else 0o644)
            entry={'mode':format(info.mode,'o'),'path':rel}
            if info.issym():
                resolved=posixpath.normpath(posixpath.join(posixpath.dirname(rel),info.linkname))
                assert resolved!='..' and not resolved.startswith(('../','/')),f'Escaping link: {rel}'
                entry.update(type='symlink',target=info.linkname);tf.addfile(info)
            else:
                assert info.isfile(),rel
                entry.update(type='file',size=info.size,sha256=sha(p))
                with p.open('rb') as f:tf.addfile(info,f)
            files.append(entry)
    archive=out/'Jerkgram-1.2.0-source.tar.xz'
    with archive.open('wb') as f:subprocess.run(['xz','-6','-T2','--stdout',str(tarpath)],stdout=f,check=True)
    tarpath.unlink()
    manifest={'schemaVersion':1,'project':'Jerkgram','version':'1.2.0','build':183,
      'upstream':{'repository':'TelegramMessenger/Telegram-iOS','tag':'release-13.2','commit':UPSTREAM},
      'builder':{'repository':'ghostbase-sg/jerkgram-telegram-builder','commit':BUILDER_SHA,'workflowRun':43516752691},
      'sourceArchive':{'filename':archive.name,'sha256':sha(archive),'size':archive.stat().st_size},'files':files}
    (out/'public-source-manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps({'entries':len(files),'archive':manifest['sourceArchive'],'manifest_sha256':sha(out/'public-source-manifest.json')},indent=2))
if __name__=='__main__':snapshot(*sys.argv[1:])
