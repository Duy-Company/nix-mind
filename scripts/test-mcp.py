#!/usr/bin/env python3
"""Live integration checks. Creates its own workbook and writes only under build/."""
import json
import pathlib
import select
import subprocess
import sys
import tempfile

root = pathlib.Path(__file__).resolve().parent.parent
binary = pathlib.Path(sys.argv[1]) if len(sys.argv)>1 else root/'build/Build/Products/Release/Nix Mind.app/Contents/MacOS/Nix Mind'
process = subprocess.Popen([str(binary),'--mcp'],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,bufsize=1)
sequence=0;checks=0

def check(value,message):
    global checks
    assert value,message
    checks+=1;print('✓',message,flush=True)

def rpc(method,params=None):
    global sequence
    sequence+=1
    process.stdin.write(json.dumps({'jsonrpc':'2.0','id':sequence,'method':method,'params':params or {}},ensure_ascii=False)+'\n');process.stdin.flush()
    assert select.select([process.stdout],[],[],25)[0], 'Timeout: '+method
    reply=json.loads(process.stdout.readline());assert reply.get('id')==sequence and 'error' not in reply,reply
    return reply['result']

def tool(name,args=None,failure=False):
    result=rpc('tools/call',{'name':name,'arguments':args or {}})
    assert bool(result.get('isError'))==failure,result
    return result if failure else result['structuredContent']

def patch(context,ops):
    return {'version':1,'documentID':context['documentID'],'baseFingerprint':context['baseFingerprint'],'operations':ops}

try:
    hello=rpc('initialize',{'protocolVersion':'2025-11-25','capabilities':{},'clientInfo':{'name':'nixmind-workbook-tests','version':'2'}})
    check(hello['serverInfo']['version']=='1.0.5','MCP initializes as version 1.0.5')
    process.stdin.write('{"jsonrpc":"2.0","method":"notifications/initialized"}\n');process.stdin.flush()
    tool_list=rpc('tools/list')
    check(len(tool_list['tools'])==14,'All 14 MCP tools expose schemas')
    check(hello['serverInfo']['title']=='Nix Mind' and 'independent native macOS' in hello['instructions'],'MCP identifies the independent Nix Mind app')
    import re
    guide=rpc('resources/read',{'uri':'nixmind://guide'})
    owned_metadata=json.dumps([hello,tool_list,guide])
    check(not re.search(r'(?<!ni)xmind',owned_metadata,re.IGNORECASE),'Built-in MCP metadata contains only the Nix Mind product identity')
    check('style' in rpc('resources/read',{'uri':'nixmind://guide'})['contents'][0]['text'],'Guide explains node style editing')
    created=tool('create_map',{'title':'Product planning'})
    doc=created['document']['id'];first=created['map']['sheetID'];ctx=created['map'];root_id=ctx['rootID']
    check(ctx['application']=='Nix Mind','Live sheet context explicitly names Nix Mind')
    args={'document_id':doc,'sheet_id':first}
    check(len(tool('read_map',args)['map']['topics'])==1,'New workbook has one central topic')
    check(len(tool('list_sheets',{'document_id':doc})['sheets'])==1,'New workbook has one sheet')
    tool('rename_sheet',{**args,'title':'Ideas'})
    names=['Discovery','Design','Build','Inspiration','People','Next steps','Research','Audience','Content','Quality','Launch','Feedback','Accessibility','Offline','Import','Export','Shortcuts','Typography','Appearance','Structure','Sheets','Outliner','MCP','Polish']
    ops=[{'action':'addTopic','id':f'branch-{i}','parentID':root_id,'title':name} for i,name in enumerate(names)]
    ops.append({'action':'updateTopic','id':'branch-0','style':{'fontFamily':'Georgia','fontSize':24,'bold':True,'italic':True,'underline':True,'alignment':'left','shape':'capsule','fillColor':'#DCEFE8FF','textColor':'#17352BFF','borderColor':'#317861FF','borderWidth':3},'structure':'leftToRight'})
    proposal=patch(ctx,ops)
    check(not tool('preview_patch',{**args,'patch':proposal})['applied'],'Preview does not apply changes')
    check(len(tool('read_map',args)['map']['topics'])==1,'Preview leaves the live workbook unchanged')
    applied=tool('apply_patch',{**args,'patch':proposal})
    check(len(applied['map']['topics'])==25,'Root supports 24 direct children over live MCP')
    styled=next(x for x in applied['map']['topics'] if x['id']=='branch-0')
    check(styled['style']['fontSize']==24 and styled['style']['shape']=='capsule' and styled['style']['bold'],'MCP applies fonts, shapes and border styling')
    check(styled['structure']=='leftToRight','MCP persists structure direction')
    tool('apply_patch',{**args,'patch':proposal},failure=True);check(True,'Stale patch fingerprints are rejected')
    ctx=tool('read_map',args)['map']
    bad=patch(ctx,[{'action':'updateTopic','id':root_id,'title':'Should not apply'},{'action':'deleteTopic','id':root_id}])
    tool('apply_patch',{**args,'patch':bad},failure=True)
    check(tool('read_map',args)['map']['baseFingerprint']==ctx['baseFingerprint'],'Invalid multi-operation edits are atomic')
    second=tool('create_sheet',{'document_id':doc,'title':'Implementation'})
    second_id=second['sheet']['id'];second_ctx=second['map'];second_args={'document_id':doc,'sheet_id':second_id}
    check(second['document']['sheetCount']==2,'Create a second sheet in the same file')
    tool('apply_patch',{**second_args,'patch':patch(second_ctx,[{'action':'updateTopic','id':second_ctx['rootID'],'title':'Implementation plan'},{'action':'addTopic','id':'step-1','parentID':second_ctx['rootID'],'title':'Build a native editor'},{'action':'addTopic','id':'step-2','parentID':second_ctx['rootID'],'title':'Verify the details'}])})
    check(len(tool('read_map',args)['map']['topics'])==25,'Editing the second sheet preserves the first sheet')
    active_before=tool('list_sheets',{'document_id':doc})['document']['activeSheetID']
    context=tool('read_map',args)['map']
    tool('apply_patch',{**args,'patch':patch(context,[{'action':'updateTopic','id':'branch-1','note':'Edited from MCP while another sheet is active'}])})
    check(tool('list_sheets',{'document_id':doc})['document']['activeSheetID']==active_before,'MCP can edit an inactive sheet without switching tabs')
    resource=rpc('resources/read',{'uri':f'nixmind://documents/{doc}/sheets/{first}/map'})
    check(json.loads(resource['contents'][0]['text'])['map']['sheetID']==first,'Specific-sheet resources return the correct context')
    third=tool('create_sheet',{'document_id':doc,'title':'Temporary'})['sheet']['id']
    tool('delete_sheet',{'document_id':doc,'sheet_id':third})
    check(len(tool('list_sheets',{'document_id':doc})['sheets'])==2,'Delete a sheet while preserving the other sheets')
    tool('select_sheet',args)
    check(tool('read_map',{'document_id':doc})['map']['sheetID']==first,'Select a sheet updates the active context')
    context=tool('read_map',args)['map']
    tool('apply_patch',{**args,'patch':patch(context,[{'action':'updateTopic','id':'branch-0','style':{'fontSize':28}}])})
    node=tool('read_topic',{**args,'topic_id':'branch-0'})['topic']
    check(node['style']['fontSize']==28 and node['style']['bold'] and node['style']['fillColor']=='#DCEFE8FF','Partial style updates preserve unrelated appearance')
    directory=pathlib.Path(tempfile.mkdtemp(prefix='workbook-smoke-',dir=root/'build'))
    native=directory/'Product planning.nixmap'
    tool('save_map',{'document_id':doc,'path':str(native)})
    saved=json.loads(native.read_text())
    check(saved['version']==2 and len(saved['sheets'])==2,'Native save writes the entire multi-sheet workbook')
    check(not tool('read_map',args)['document']['hasUnsavedChanges'],'Native save clears the edited marker')
    saved_style=next(x for x in saved['sheets'][0]['map']['topics'] if x['id']=='branch-0')['style']
    check(saved_style['fontSize']==28 and saved_style['italic'] and saved_style['underline'],'Native save preserves typography and formatting')
    xmind=directory/'Product planning.xmind';tool('export_map',{'document_id':doc,'path':str(xmind)})
    import zipfile
    with zipfile.ZipFile(xmind) as archive: sheets=json.loads(archive.read('content.json'))
    check(len(sheets)==2,'Map archive export contains both sheets')
    imported=tool('open_map',{'path':str(xmind)})
    check(imported['document']['sheetCount']==2,'Map archive import recreates multiple sheets in the app')
    imported_first=tool('list_sheets',{'document_id':imported['document']['id']})['sheets'][0]['id']
    roundtrip=tool('read_map',{'document_id':imported['document']['id'],'sheet_id':imported_first})['map']
    check(next(x for x in roundtrip['topics'] if x['id']=='branch-0')['style']==saved_style,'Map archive import preserves Nix Mind style metadata')
    for ext in ['mm','md']:
        path=directory/f'Implementation.{ext}';tool('export_map',{**second_args,'path':str(path)})
        check(path.exists() and path.stat().st_size>60,'Export selected sheet as '+ext)
    md=directory/'All sheets.md';tool('export_map',{'document_id':doc,'path':str(md)})
    check('Ideas' in md.read_text() and 'Implementation' in md.read_text(),'Markdown export includes all sheets when none is specified')
    tool('export_map',{'document_id':doc,'path':str(md)},failure=True);check(True,'Existing files require explicit overwrite')
    template=rpc('resources/templates/list')['resourceTemplates']
    check(any('{sheet_id}' in x['uriTemplate'] for x in template),'MCP advertises sheet-aware resource templates')
    single=tool('create_map',{'title':'Last-sheet guard'})['document']['id']
    only=tool('list_sheets',{'document_id':single})['sheets'][0]['id']
    tool('delete_sheet',{'document_id':single,'sheet_id':only},failure=True);check(True,'The final sheet cannot be deleted')
    tool('save_map',{'document_id':single,'path':str(directory/'Last-sheet guard.nixmap')})
    # Leave the primary workbook selected and retain IDs for UI verification.
    tool('select_sheet',args);tool('open_map',{'path':str(native)})
    (root/'build/mcp-last-test.json').write_text(json.dumps({'sessionID':doc,'sheetID':first,'secondSheetID':second_id,'directory':str(directory),'path':str(native)},indent=2))
    print(f'PASS: {checks} MCP checks\nArtifacts: {directory}',flush=True)
finally:
    process.stdin.close()
    try: process.wait(timeout=5)
    except subprocess.TimeoutExpired: process.terminate();process.wait(timeout=5)
