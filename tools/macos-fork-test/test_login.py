#!/usr/bin/env python3
# SPDX-FileCopyrightText: (C) 2026 lxf82dev <lxf82dev@gmail.com>
# SPDX-License-Identifier: GPL-2.0-only WITH LicenseRef-OpenSSL-Exception

"""Exercise login installation and recovery without touching real services."""
import json
import os
import plistlib
import subprocess
import tempfile
from pathlib import Path

source = Path(__file__).with_name('permanent-login.zsh').read_text()
legacy = ['local.deskflow.mx-middle-relay', 'local.deskflow.mx-awdl-menu']
fork = 'local.deskflow.fork-login'
stub = '''#!/usr/bin/env python3
import json,os,plistlib,sys
from pathlib import Path
ledger=Path(os.environ['DESKFLOW_LOGIN_TEST_LEDGER'])
data=json.loads(ledger.read_text()); name=Path(sys.argv[0]).name; args=sys.argv[1:]
data['calls'].append([name,*args]); result=0
if name=='launchctl':
    operation=args[0]
    label=args[1].rsplit('/',1)[-1] if len(args)>1 else ''
    if operation=='print-disabled':
        for item,value in data['disabled'].items(): print('"'+item+'" => '+('disabled' if value else 'enabled'))
    elif operation=='print': result=0 if label in data['loaded'] else 113
    elif operation in ('enable','disable'): data['disabled'][label]=operation=='disable'
    elif operation=='bootout':
        if label in data['loaded']: data['loaded'].remove(label)
    elif operation=='bootstrap':
        with open(args[2],'rb') as stream: item=plistlib.load(stream)
        label=item['Label']
        if data['disabled'].get(label,False): result=1
        elif label not in data['loaded']: data['loaded'].append(label)
    else: result=2
elif name in ('pkill','pgrep'): result=1
ledger.write_text(json.dumps(data)); sys.exit(result)
'''

for case in ('roundtrip', 'disabled-before', 'autostart-off', 'cleanup-roundtrip'):
    with tempfile.TemporaryDirectory(prefix='deskflow-login-test-') as directory:
        root = Path(directory)
        home = root/'user'
        bins = root/'bin'; bins.mkdir()
        state = home/'Library/Application Support/DeskflowForkTest'
        state.mkdir(parents=True)
        backup = state/'backup-original'; backup.mkdir()
        prefs = home/'Library/Deskflow'; prefs.mkdir(parents=True)
        (prefs/'Deskflow.conf').write_text('[gui]\nstartCoreWithGui='+('false' if case=='autostart-off' else 'true')+'\n[core]\nprocessMode=1\n')
        (backup/'Deskflow').mkdir()
        (backup/'Deskflow/Deskflow.conf').write_text('original settings\n')
        (backup/'control').write_text('auto\n')
        (backup/'loaded-agents').write_text('\n'.join(legacy)+'\n')
        (state/'active').write_text(str(backup)+'\n')
        original=root/'system/Applications/Deskflow.app'
        (original/'Contents').mkdir(parents=True)
        with (original/'Contents/Info.plist').open('wb') as stream:
            plistlib.dump({'CFBundleIdentifier':'org.deskflow.deskflow'},stream)
        control = home/'Library/Application Support/DeskflowMXAWDL/control'
        control.parent.mkdir(parents=True); control.write_text('auto\n')
        app = home/'Applications/Deskflow Fork Test.app/Contents'
        (app/'MacOS').mkdir(parents=True)
        (app/'MacOS/Deskflow').write_text('unchanged app')
        with (app/'Info.plist').open('wb') as stream:
            plistlib.dump({'CFBundleIdentifier':'dev.lxf82.deskflow.forktest','CFBundleName':'Deskflow Fork Test','CFBundleDisplayName':'Deskflow Fork Test'},stream)
        agents = home/'Library/LaunchAgents'; agents.mkdir(parents=True)
        for label in legacy:
            with (agents/(label+'.plist')).open('wb') as stream: plistlib.dump({'Label':label},stream)
        if case=='cleanup-roundtrip':
            for title,identifier in [('Deskflow MX Relay','local.deskflow.mx-middle-relay'),('Deskflow Smooth Mode','local.deskflow.mx-smooth-mode')]:
                helper=home/'Applications'/(title+'.app')/'Contents'
                helper.mkdir(parents=True)
                with (helper/'Info.plist').open('wb') as stream: plistlib.dump({'CFBundleIdentifier':identifier},stream)
        ledger = root/'ledger.json'
        ledger.write_text(json.dumps({'calls':[], 'loaded':[], 'disabled':{legacy[0]:False,legacy[1]:case=='disabled-before'}}))
        for name in ('launchctl','codesign','open','pkill','pgrep'):
            executable = bins/name; executable.write_text(stub); executable.chmod(0o755)
        # Rewrite only the generated test copy: no production test-mode switch,
        # no HOME override, and no real process/service commands can run.
        transformed = source.replace('$HOME', '${DESKFLOW_LOGIN_TEST_HOME}')
        transformed = transformed.replace('/Applications/Deskflow.app', str(original))
        for command_path in ('/bin/launchctl','/usr/bin/codesign','/usr/bin/open','/usr/bin/pkill','/usr/bin/pgrep'):
            transformed=transformed.replace(command_path,'"$DESKFLOW_LOGIN_TEST_BIN/'+Path(command_path).name+'"')
        script=root/'test-login.zsh'; script.write_text(transformed)
        env=dict(os.environ,DESKFLOW_LOGIN_TEST_HOME=str(home),DESKFLOW_LOGIN_TEST_BIN=str(bins),DESKFLOW_LOGIN_TEST_LEDGER=str(ledger))
        def run(action, success=True):
            result=subprocess.run(['/bin/zsh',str(script),action],env=env,text=True,capture_output=True)
            assert (result.returncode==0)==success, result.stdout+result.stderr
            return json.loads(ledger.read_text())
        installed=run('install',case!='autostart-off')
        if case=='autostart-off':
            assert not (agents/(fork+'.plist')).exists()
            assert not (state/'login-backup').exists()
            assert installed['disabled'][legacy[0]] is False
        else:
            with (agents/(fork+'.plist')).open('rb') as stream: agent=plistlib.load(stream)
            assert agent['ProgramArguments']==[str(bins/'open'),'-g',str(app.parent)]
            assert agent['RunAtLoad'] is True and 'KeepAlive' not in agent
            assert all(installed['disabled'][label] for label in legacy)
            assert fork in installed['loaded']
            assert (app/'MacOS/Deskflow').read_text()=='unchanged app'
            run('install')
            if case=='cleanup-roundtrip':
                cleaned=run('cleanup')
                renamed=home/'Applications/Deskflow+.app'
                assert renamed.is_dir() and not app.parent.exists()
                with (renamed/'Contents/Info.plist').open('rb') as stream:
                    info=plistlib.load(stream)
                assert info['CFBundleName']=='Deskflow+' and info['CFBundleDisplayName']=='Deskflow+'
                assert (renamed/'Contents/MacOS/Deskflow').read_text()=='unchanged app'
                for title in ['Deskflow MX Relay','Deskflow Smooth Mode']:
                    assert not (home/'Applications'/(title+'.app')).exists()
                    assert (state/'retired-helpers/apps'/(title+'.app')).is_dir()
                assert all(not (agents/(label+'.plist')).exists() for label in legacy)
                with (agents/(fork+'.plist')).open('rb') as stream:
                    assert plistlib.load(stream)['ProgramArguments'][-1]==str(renamed)
                run('status')
                current_prefs=(prefs/'Deskflow.conf').read_text()
                (prefs/'Deskflow.conf').write_text(current_prefs.replace('processMode=1','processMode=0'))
                run('retire-original',False)
                assert original.is_dir()
                (prefs/'Deskflow.conf').write_text(current_prefs.replace('processMode=1','processMode=unknown'))
                run('status',False)
                (prefs/'Deskflow.conf').write_text(current_prefs.replace('[core]\nprocessMode=1\n',''))
                run('status')  # Missing core/processMode uses the macOS desktop default.
                disabled=json.loads(ledger.read_text()); disabled['disabled'][fork]=True
                ledger.write_text(json.dumps(disabled)); run('retire-original',False)
                assert original.is_dir()
                disabled=json.loads(ledger.read_text()); disabled['disabled'][fork]=False
                ledger.write_text(json.dumps(disabled))
                with (original/'Contents/Info.plist').open('wb') as stream:
                    plistlib.dump({'CFBundleIdentifier':'unrelated.app'},stream)
                run('retire-original',False)
                assert original.is_dir()
                with (original/'Contents/Info.plist').open('wb') as stream:
                    plistlib.dump({'CFBundleIdentifier':'org.deskflow.deskflow'},stream)
                run('retire-original')
                archived=state/'retired-original/Deskflow.app'
                assert archived.is_dir() and not original.exists()
                run('retire-original')
                first_calls=len(json.loads(ledger.read_text())['calls'])
                repeated=run('cleanup')
                assert not any(call[0]=='codesign' and '--force' in call for call in repeated['calls'][first_calls:])
                recovered=run('restore')
                assert any(call==['open',str(archived)] for call in recovered['calls'])
                assert all((agents/(label+'.plist')).is_file() for label in legacy)
                assert all((home/'Applications'/(title+'.app')).is_dir() for title in ['Deskflow MX Relay','Deskflow Smooth Mode'])
                assert (prefs/'Deskflow.conf').read_text()=='original settings\n'
                print('PASS:',case)
                continue
            undone=run('undo')
            assert not (agents/(fork+'.plist')).exists()
            assert undone['disabled'][legacy[0]] is False
            assert undone['disabled'][legacy[1]]==(case=='disabled-before')
            if case=='roundtrip':
                run('install')
                restored=run('restore')
                assert not (state/'active').exists()
                assert (prefs/'Deskflow.conf').read_text()=='original settings\n'
                assert all(label in restored['loaded'] for label in legacy)
                assert any(call==['open',str(original)] for call in restored['calls'])
        print('PASS:',case)
print('No real services, processes, app bundles or user settings were changed.')
