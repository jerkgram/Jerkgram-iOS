"""Verify the three release assets, install public source, commit/tag, publish."""
from pathlib import Path,PurePosixPath
import hashlib,json,os,shutil,subprocess,sys,tarfile
from package_source import sha
TAG='v1.2.0'; REPO='jerkgram/Jerkgram-iOS'; VERSION='1.2.0'
def run(*args,**kw):return subprocess.check_output(args,text=True,**kw).strip()
def api(path,*args):return json.loads(run('gh','api',path,*args))
def publish(repo,assets,expected):
    repo,assets=Path(repo).resolve(),Path(assets).resolve(); expected=json.loads(Path(expected).read_text());os.chdir(repo)
    assert os.environ['GITHUB_REPOSITORY']==REPO
    assert api('repos/'+REPO)['default_branch']=='main'
    assert not run('git','ls-remote','--tags','origin','refs/tags/'+TAG), 'Refuse existing tag'
    manifest=json.loads((assets/'public-source-manifest.json').read_text())
    fingerprint=hashlib.sha256(json.dumps(manifest['files'],sort_keys=True,separators=(',',':'),ensure_ascii=False).encode()).hexdigest()
    assert fingerprint==expected['sourceLeavesSha256'], 'Source file contents/modes/links differ from local snapshot: '+fingerprint
    print('Exact local source leaves VERIFIED: '+fingerprint,flush=True)
    # XZ releases can produce different bytes for identical tar contents. Pin the
    # entire local leaf manifest, then record and re-download verify actual assets.
    for name,row in expected['assets'].items():
        p=assets/name
        if name=='Jerkgram-1.2.0.ipa':assert p.stat().st_size==row['size'] and sha(p)==row['sha256'],name
        else:expected['assets'][name]={'size':p.stat().st_size,'sha256':sha(p)}
    assert manifest['sourceArchive']=={'filename':'Jerkgram-1.2.0-source.tar.xz',**expected['assets']['Jerkgram-1.2.0-source.tar.xz']}

    assert manifest['build']==183 and manifest['builder']['commit']==expected['builderCommit']
    records={x['path']:x for x in manifest['files']};actual={};prefix='Jerkgram-1.2.0-source/'
    destination=repo.parent/'verified-source';destination.mkdir()
    with tarfile.open(assets/'Jerkgram-1.2.0-source.tar.xz') as tf:
        for item in tf:
            assert item.name.startswith(prefix);rel=item.name[len(prefix):]
            assert rel and '..' not in PurePosixPath(rel).parts and '.git' not in PurePosixPath(rel).parts
            assert not rel.startswith(('build-input/','.github/workflows/'))
            row={'mode':format(item.mode,'o'),'path':rel}
            if item.issym():row.update(type='symlink',target=item.linkname)
            else:
                assert item.isfile();row.update(type='file',size=item.size,sha256=hashlib.sha256(tf.extractfile(item).read()).hexdigest())
            assert rel not in actual;actual[rel]=row
        assert actual==records, 'Manifest content mismatch'
        # Python data filter also refuses links escaping the output tree.
        tf.extractall(destination,filter='data')
    source=destination/prefix[:-1]
    ident=(source/'submodules/TelegramPresentationData/Sources/JerkgramStrings.swift').read_text()
    for key,value in [('displayVersion','1.2.0 Stable'),('build','183'),('telegramBase','13.2')]:assert f'public static let {key} = "{value}"' in ident
    releases=[r for r in api('repos/'+REPO+'/releases?per_page=100') if r['tag_name']==TAG]
    assert len(releases)<=1
    notes=(Path(__file__).parent/'release-notes.md').read_text()
    if releases:assert releases[0]['draft'] and not releases[0]['assets'],'Existing nonempty release; inspect before resuming'
    else:
        run('gh','release','create',TAG,'--repo',REPO,'--target','main','--title','Jerkgram 1.2.0','--notes-file',str(Path(__file__).parent/'release-notes.md'),'--draft')
    run('gh','release','upload',TAG,*[str(assets/n) for n in expected['assets']],'--repo',REPO)
    release=next(r for r in api('repos/'+REPO+'/releases?per_page=100') if r['tag_name']==TAG)
    assert release['draft'] and len(release['assets'])==3
    for asset in release['assets']:
        row=expected['assets'][asset['name']];assert asset['size']==row['size']
        # Verify bytes uploaded to the draft, not just local inputs.
        check=assets/('check-'+asset['name'])
        subprocess.run(['gh','release','download',TAG,'--repo',REPO,'--pattern',asset['name'],'--output',str(check)],check=True)
        assert sha(check)==row['sha256'];check.unlink()
    overlay=repo.parent/'public-overlay';overlay.mkdir()
    paths=['.github','assets','CONTRIBUTING.md','LICENSE','README.md','README_RU.md','SECURITY.md','SUPPORT.md','THIRD_PARTY_NOTICES.md','UPSTREAM.md']
    docs=['BUILDING.md','JERKGRAM_RELEASE.schema.json','RELEASES.md','RELEASE_TEMPLATE.md','SOURCE_TRANSPARENCY.md']
    for name in paths:
        p=repo/name;assert p.exists(),name
        if p.is_dir():shutil.copytree(p,overlay/name)
        else:shutil.copy2(p,overlay/name)
    (overlay/'docs').mkdir()
    for name in docs:shutil.copy2(repo/'docs'/name,overlay/'docs'/name)
    for p in repo.iterdir():
        if p.name=='.git':continue
        if p.is_dir() and not p.is_symlink():shutil.rmtree(p)
        else:p.unlink()
    shutil.copytree(source,repo,dirs_exist_ok=True,symlinks=True)
    for name in paths:
        p=repo/name
        if p.is_dir():shutil.rmtree(p)
        elif p.exists() or p.is_symlink():p.unlink()
        if (overlay/name).is_dir():shutil.copytree(overlay/name,p)
        else:shutil.copy2(overlay/name,p)
    (repo/'docs').mkdir(exist_ok=True)
    for name in docs:shutil.copy2(overlay/'docs'/name,repo/'docs'/name)
    shutil.copy2(assets/'public-source-manifest.json',repo/'public-source-manifest.json')
    metadata={'$schema':'./docs/JERKGRAM_RELEASE.schema.json','schemaVersion':1,'project':'Jerkgram','repository':REPO,'status':'stable','jerkgramVersion':VERSION,'buildNumber':183,'upstream':manifest['upstream'],'publicSourceTag':TAG}
    for key,name in [('ipa','Jerkgram-1.2.0.ipa'),('sourceSnapshot','Jerkgram-1.2.0-source.tar.xz'),('sourceManifest','public-source-manifest.json')]:metadata[key]={'filename':name,'sha256':expected['assets'][name]['sha256']}
    (repo/'JERKGRAM_RELEASE.json').write_text(json.dumps(metadata,indent=2)+'\n')
    for name in ['README.md','README_RU.md','UPSTREAM.md']+['docs/'+x for x in docs if x!='JERKGRAM_RELEASE.schema.json']+['assets/readme/hero.svg','assets/readme/provenance.svg']:
        p=repo/name;text=p.read_text();text=text.replace('1.1.0','1.2.0').replace('release-13.0.0','release-13.2').replace('f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838',manifest['upstream']['commit']).replace('Telegram%20iOS-13.0-','Telegram%20iOS-13.2-').replace('Telegram iOS 13.0','Telegram iOS 13.2').replace('TELEGRAM 13.0','TELEGRAM 13.2');p.write_text(text)
    with (repo/'docs/RELEASES.md').open('a') as f:f.write('\n## 1.2.0 / Build183\n\n'+notes+'\n')
    (repo/'.github/workflows/publish-source-once.yml').unlink()
    shutil.rmtree(repo/'.github/release-tools-120')
    run('git','config','user.name','github-actions[bot]');run('git','config','user.email','41898282+github-actions[bot]@users.noreply.github.com')
    run('git','add','-A');run('git','commit','-m','Publish Jerkgram 1.2.0 source / Build183')
    commit=run('git','rev-parse','HEAD');run('git','tag','-a',TAG,'-m','Jerkgram 1.2.0 / Build183')
    run('git','push','--atomic','origin','HEAD:main',TAG)
    assert run('git','ls-remote','origin','refs/tags/'+TAG+'^{}').split()[0]==commit
    run('gh','release','edit',TAG,'--repo',REPO,'--draft=false','--latest')
    final=api('repos/'+REPO+'/releases/tags/'+TAG);assert not final['draft']
    print(json.dumps({'published':final['html_url'],'sourceCommit':commit,'publishedAt':final['published_at']},indent=2))
if __name__=='__main__':publish(*sys.argv[1:])
