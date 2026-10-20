"""Author a separate render-only action fixture. Not connected multiplayer.

References a separately generated PRIVATE action-clip cache. This archive packs
only authored entity/graph resources; the cache must never be redistributed.
"""
from __future__ import annotations
import argparse
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess

spec = importlib.util.spec_from_file_location('base_locomotion', Path(__file__).with_name('build_assets.py'))
base = importlib.util.module_from_spec(spec)
spec.loader.exec_module(base)
ENTITY = r'base\cp2077coop\entities\player_actions_fixture.ent'
GRAPH = r'base\cp2077coop\animations\player_actions_fixture.animgraph'
CACHE = tuple(r'base\cp2077coop\private\player_'+name+'.anims' for name in ('stealth','rifle','handgunboth'))
UPPER_BONES = ('Spine','Spine1','Spine2','Spine3','LeftShoulder','RightShoulder',
    'Neck','Neck1','Head','LeftArm','RightArm','LeftForeArm','RightForeArm',
    'LeftHand','RightHand','WeaponLeft','WeaponRight','LeftEye','RightEye') + tuple(
        side+'InHand'+finger for side in ('Left','Right') for finger in ('Thumb','Index','Middle','Ring','Pinky')) + tuple(
        side+'Hand'+finger+str(index) for side in ('Left','Right')
        for finger in ('Thumb','Index','Middle','Ring','Pinky') for index in (1,2,3)
        if finger!='Thumb' or index<3)
UPPER_CLIPS = tuple('cp_coop_'+profile+'_'+clip for profile in ('rifle','handgunboth')
    for clip in ('ovr_idle','ovr_walk','ovr_sprint','aim_ovr_idle','aim_ovr_walk'))
LOWER_BONES=('Hips','LeftUpLeg','RightUpLeg','LeftLeg','RightLeg',
             'LeftFoot','RightFoot','LeftToeBase','RightToeBase')


def profile_values(weapon_profile,directional_walk=False):
    if weapon_profile not in ('rifle','shotgundual'):raise ValueError('Unsupported weapon pose profile')
    # The Palica bank's aim is a smart-shotgun hip-fire hold. Keep the inspected
    # shoulder-aim clips for the iron-sight Igla while comparing shotgun ready.
    profiles=('stealth','rifle','handgunboth') if weapon_profile=='rifle' else ('stealth','shotgundual','rifle','handgunboth')
    cache=tuple(r'base\cp2077coop\private\player_'+name+'.anims' for name in profiles)
    if directional_walk:cache += (r'base\cp2077coop\private\player_directional_neutral.anims',
                                  r'base\cp2077coop\private\player_crouch_backward.anims')
    clips=tuple('cp_coop_'+weapon_profile+'_'+clip for clip in ('ovr_idle','ovr_walk','ovr_sprint'))+tuple(
        'cp_coop_rifle_'+clip for clip in ('aim_ovr_idle','aim_ovr_walk'))+tuple(
        'cp_coop_handgunboth_'+clip for clip in ('ovr_idle','ovr_walk','ovr_sprint','aim_ovr_idle','aim_ovr_walk'))
    return cache,clips


def sources(weapon_profile='rifle',aim_fixture=False,directional_walk=False):
    cache,upper_clips=profile_values(weapon_profile,directional_walk)
    entity,graph=base.sources('full')
    base.validate(entity,graph,'full')
    er=entity['Data']['RootChunk']
    for components in (er['components'],er['compiledData']['Data']['Chunks'][1:]):
        a=components[0]
        a['graph']=base.resource(GRAPH,'Obligatory')
        for path in cache:
            setup=copy.deepcopy(a['animations']['gameplay'][0])
            setup['animSet']=base.resource(path)
            a['animations']['gameplay'].append(setup)
    er['resolvedDependencies'] += [base.resource(x,'Soft') for x in (GRAPH,*cache)]
    er['resolvedDependencies'] = [x for x in er['resolvedDependencies'] if x['DepotPath']['$value'] != base.GRAPH]
    gr=graph['Data']['RootChunk']
    definitions={v['HandleId']:v['Data'] for v in base.walk(gr) if 'HandleId' in v}
    next_id=max(map(int,definitions))+1
    def data(h): return definitions[h.get('HandleId',h.get('HandleRefId'))]
    root=data(gr['rootNode']);output=data(root['nodes'][0]);standing=output['node']
    # Engine switch timers slow with local world dilation. Gait selection already
    # has hysteresis in Lua; this layer must not add seconds of pose catch-up.
    data(standing['node'])['blendTime']=0
    proto={v.get('$type'):copy.deepcopy(v) for v in definitions.values()}
    new_nodes=[]
    def add(value,is_node=True):
        nonlocal next_id
        handle={'HandleId':str(next_id),'Data':value};next_id+=1
        definitions[handle['HandleId']]=value
        if is_node:new_nodes.append(handle)
        return {'HandleRefId':handle['HandleId']} if is_node else handle
    def link(h,kind='animPoseLink'):return {'$type':kind,'node':h}
    variables=data(gr['variables'])
    def variable(name,maximum,minimum=0):
        value=copy.deepcopy(proto['animAnimVariableFloat'])
        value['name']=base.cname(name);value.update(min=minimum,max=maximum,default=0,value=0)
        variables['floatVariables'].append(add(value,False))
        reader=copy.deepcopy(proto['animAnimNode_FloatVariable']);reader['variableName']=base.cname(name)
        return add(reader)
    stance=variable('cp_coop_stance',1)
    moving=variable('cp_coop_crouch_motion',1)
    weapon=variable('cp_coop_weapon_pose',len(upper_clips)-1)
    weight=variable('cp_coop_weapon_weight',1)
    previous_weapon=variable('cp_coop_weapon_previous_pose',len(upper_clips)-1)
    weapon_blend=variable('cp_coop_weapon_blend',1)
    previous_progress=variable('cp_coop_weapon_previous_progress',1)
    previous_phase=variable('cp_coop_loco_previous_phase',5)
    gait_progress=variable('cp_coop_loco_previous_progress',1)
    gait_weight=variable('cp_coop_loco_blend_weight',1)
    if directional_walk:
        direction=variable('cp_coop_walk_direction',3)
        previous_direction=variable('cp_coop_walk_previous_direction',3)
        direction_blend=variable('cp_coop_walk_direction_blend',1)
        direction_progress=variable('cp_coop_walk_previous_progress',1)
        direction_weight=variable('cp_coop_walk_direction_weight',1)
        gait_direction=variable('cp_coop_loco_previous_direction',3)
        gait_direction_weight=variable('cp_coop_loco_previous_direction_weight',1)
        crouch_progress=variable('cp_coop_crouch_progress',1)
        crouch_backward=variable('cp_coop_crouch_backward',1)
    progress=next({'HandleRefId':k} for k,v in definitions.items()
        if v.get('$type')=='animAnimNode_FloatVariable' and v['variableName']==base.cname('cp_coop_loco_progress'))
    def clip(name,sampled=False,reader=None):
        value=copy.deepcopy(proto['animAnimNode_SkFrameAnim' if sampled else 'animAnimNode_SkAnim'])
        value['animation']=base.cname(name);value['isLooped']=int(not sampled)
        for key in ('applyMotion','collectEvents','fireAnimLoopEvent','resume'):value[key]=0
        if sampled:
            value['progressLink']=link(reader or progress,'animFloatLink')
            for key in ('timeLink','frameLink'):value[key]={'$type':'animFloatLink','node':None}
        return link(add(value))
    def switch(inputs,reader):
        value=copy.deepcopy(proto['animAnimNode_Switch'])
        value.update(inputNodes=inputs,numInputs=len(inputs),blendTime=0,weightNode=link(reader,'animFloatLink'))
        return link(add(value))
    def blend(first,second,reader):
        return link(add({'$type':'animAnimNode_Blend2','id':4294967295,
            'minInputValue':0,'maxInputValue':1,'timeWarpingEnabled':0,'syncMethod':None,
            'firstInputNode':first,'secondInputNode':second,'weightNode':link(reader,'animFloatLink')}))
    def lower_override(first,second,reader):
        # Only the separately qualified forward-hip derivative may enter here.
        # Raw combat hips rotate the baseline torso even through a lower mask.
        # Keep the baseline spine/shoulders/arms and copy only corrected legs.
        return link(add({'$type':'animAnimNode_BlendOverride','id':4294967295,
            'inputNode':first,'overrideInputNode':second,'weightNode':link(reader,'animFloatLink'),
            'bones':[{'$type':'animOverrideBlendBoneInfo','transformIndex':{'$type':'animTransformIndex','name':base.cname(name)},'weight':1}
                     for name in LOWER_BONES],
            'blendAllTracks':0,'blendTrackMode':'AGBT_Interpolate','tracks':[],
            'getDeltaMotionFromOverride':0,'timeWarpingEnabled':0,'syncMethod':None,'blendMethod':None,'postProcess':None}))
    if directional_walk:
        names=tuple('cp_coop_directional_neutral_'+n for n in ('walk_0','walk_090','walk_180','walk_270'))
        selected=blend(switch([clip(n,True,direction_progress) for n in names],previous_direction),
                       switch([clip(n,True) for n in names],direction),direction_blend)
        lower_selector=data(standing['node'])
        lower_selector['inputNodes'][1]=lower_override(lower_selector['inputNodes'][1],selected,direction_weight)
    # Explicit real-clock weights replace instant lower phase changes. Freeze
    # the departing gait rather than running its engine clock after a stop.
    previous_clips=[clip(name,i!=0,gait_progress) for i,name in enumerate(base.CLIPS)]
    if directional_walk:
        previous_clips[1]=lower_override(previous_clips[1],
            switch([clip(n,True,gait_progress) for n in names],gait_direction),gait_direction_weight)
    standing=blend(standing,switch(previous_clips,previous_phase),gait_weight)
    crouch_walk=clip('cp_coop_stealth_walk_0',True,crouch_progress if directional_walk else progress)
    if directional_walk:
        crouch_walk=blend(crouch_walk,clip('cp_coop_crouch_backward_walk_180',True,crouch_progress),crouch_backward)
    crouch=blend(clip('cp_coop_stealth_idle_low_unarmed'),crouch_walk,moving)
    lower=blend(standing,crouch,stance)
    def weapon_clips(reader):
        return [clip(name,'walk' in name or 'sprint' in name,reader) for name in upper_clips]
    upper=blend(switch(weapon_clips(previous_progress),previous_weapon),
                switch(weapon_clips(progress),weapon),weapon_blend)
    override={'$type':'animAnimNode_BlendOverride','id':4294967295,
        'inputNode':lower,'overrideInputNode':upper,'weightNode':link(weight,'animFloatLink'),
        'bones':[{'$type':'animOverrideBlendBoneInfo','transformIndex':{'$type':'animTransformIndex','name':base.cname(name)},'weight':1}
                 for name in UPPER_BONES],
        'blendAllTracks':0,'blendTrackMode':'AGBT_Interpolate','tracks':[],
        'getDeltaMotionFromOverride':0,'timeWarpingEnabled':0,'syncMethod':None,'blendMethod':None,'postProcess':None}
    result=link(add(override))
    if aim_fixture:
        # Private engine qualification only. No production capture/wire consumer.
        # Model-space spine rotations carry hands and their passive weapon child,
        # without rotating the pelvis, feet or entity/world transform.
        for name,axis,limit in (('pitch','X_Axis',40),('yaw','Z_Axis',45)):
            reader=variable('cp_coop_aim_'+name,limit,-limit)
            result=link(add({'$type':'animAnimNode_RotateBone','id':4294967295,
                'inputNode':result,'angleNode':link(reader,'animFloatLink'),
                'minValueNode':{'$type':'animFloatLink','node':None},
                'maxValueNode':{'$type':'animFloatLink','node':None},
                'bone':{'$type':'animTransformIndex','name':base.cname('Spine2')},
                'axis':axis,'scale':1,'biasAngle':0,'minAngle':-limit,'maxAngle':limit,
                'clampRotation':1,'useIncrementalMode':0,'resetOnActivation':1,'inModelSpace':1}))
    output['node']=result
    root['nodes'] += new_nodes
    gr['nodesToInit'] += [{'HandleRefId':h['HandleId']} for h in new_nodes]
    # WolvenKit's JSON reader resolves references as it reads, so definitions
    # must occur at first use rather than later in the root registration list.
    graph=inline_first_use(graph)
    return entity,graph


def inline_first_use(doc):
    definitions={v['HandleId']:v['Data'] for v in base.walk(doc) if 'HandleId' in v}
    emitted=set()
    def visit(value):
        if isinstance(value,list):return [visit(v) for v in value]
        if not isinstance(value,dict):return value
        if 'HandleId' in value or 'HandleRefId' in value:
            ident=value.get('HandleId',value.get('HandleRefId'))
            if ident in emitted:return {'HandleRefId':ident}
            emitted.add(ident)
            return {'HandleId':ident,'Data':visit(definitions[ident])}
        return {k:visit(v) for k,v in value.items()}
    return visit(doc)


def validate(entity,graph,weapon_profile='rifle',aim_fixture=False,directional_walk=False):
    cache,upper_clips=profile_values(weapon_profile,directional_walk)
    er=entity['Data']['RootChunk'];gr=graph['Data']['RootChunk']
    # Reuse the base profile's binding/LOD/no-AI checks without weakening them.
    normalized=copy.deepcopy(entity)
    for components in (normalized['Data']['RootChunk']['components'],normalized['Data']['RootChunk']['compiledData']['Data']['Chunks'][1:]):
        animated=components[0]
        if [s['animSet'] for s in animated['animations']['gameplay'][-len(cache):]] != [base.resource(x) for x in cache]:
            raise ValueError('Private clip cache references missing')
        animated['animations']['gameplay']=animated['animations']['gameplay'][:-len(cache)]
        animated['graph']=base.resource(base.GRAPH,'Obligatory')
    base.validate(normalized,base.sources('full')[1],'full')
    if er['entity']['Data']['$type']!='entEntity':raise ValueError('Pure entity required')
    allowed={'entAnimatedComponent','entSkinnedMeshComponent','entAnimationControllerComponent'}
    if any(c['$type'] not in allowed for c in er['components']):raise ValueError('Gameplay component forbidden')
    if er['components'][0]['graph']!=base.resource(GRAPH,'Obligatory'):raise ValueError('Wrong action graph')
    definitions={}
    for value in base.walk(gr):
        if 'HandleId' in value:
            if value['HandleId'] in definitions:raise ValueError('Duplicate graph handle')
            definitions[value['HandleId']]=value['Data']
    if any(v['HandleRefId'] not in definitions for v in base.walk(gr) if 'HandleRefId' in v):
        raise ValueError('Unresolved graph handle')
    def data(h):return definitions[h.get('HandleId',h.get('HandleRefId'))]
    root=data(gr['rootNode']);output=data(root['nodes'][0])
    if root['$type']!='animAnimNode_Root' or output['$type']!='animAnimNode_Output':raise ValueError('Wrong active root/output')
    variables=data(gr['variables'])['floatVariables']
    expected=[('cp_coop_loco_phase',5),('cp_coop_loco_progress',1),('cp_coop_stance',1),
        ('cp_coop_crouch_motion',1),('cp_coop_weapon_pose',len(upper_clips)-1),('cp_coop_weapon_weight',1),
        ('cp_coop_weapon_previous_pose',len(upper_clips)-1),('cp_coop_weapon_blend',1),('cp_coop_weapon_previous_progress',1),
        ('cp_coop_loco_previous_phase',5),('cp_coop_loco_previous_progress',1),('cp_coop_loco_blend_weight',1)]
    if directional_walk:expected += [('cp_coop_walk_direction',3),('cp_coop_walk_previous_direction',3),
        ('cp_coop_walk_direction_blend',1),('cp_coop_walk_previous_progress',1),('cp_coop_walk_direction_weight',1),
        ('cp_coop_loco_previous_direction',3),('cp_coop_loco_previous_direction_weight',1),
        ('cp_coop_crouch_progress',1),('cp_coop_crouch_backward',1)]
    if aim_fixture:expected += [('cp_coop_aim_pitch',40),('cp_coop_aim_yaw',45)]
    if [(data(v)['name']['$value'],data(v)['max']) for v in variables]!=expected:
        raise ValueError('Wrong action variables')
    if any(data(v)[k]!=0 for v in variables for k in ('default','value')):
        raise ValueError('Non-neutral action defaults')
    for v in variables:
        value=data(v);minimum={'cp_coop_aim_pitch':-40,'cp_coop_aim_yaw':-45}.get(value['name']['$value'],0)
        if value['min']!=minimum:raise ValueError('Wrong action variable bounds')
    for value in definitions.values():
        if value.get('$type') in ('animAnimNode_SkAnim','animAnimNode_SkFrameAnim'):
            if any(value[k] for k in ('applyMotion','collectEvents','fireAnimLoopEvent','resume')):
                raise ValueError('Gameplay/root motion forbidden')
    overrides=[v for v in definitions.values() if v.get('$type')=='animAnimNode_BlendOverride']
    if len(overrides)!=(3 if directional_walk else 1):raise ValueError('Wrong masked overlay count')
    upper_overlays=[v for v in overrides if [b['transformIndex']['name']['$value'] for b in v['bones']]==list(UPPER_BONES)]
    if len(upper_overlays)!=1:raise ValueError('One upper-body overlay required')
    overlay=upper_overlays[0]
    terminal=data(output['node']['node'])
    rotations=[v for v in definitions.values() if v.get('$type')=='animAnimNode_RotateBone']
    if len(rotations)!=(2 if aim_fixture else 0):raise ValueError('Unexpected aim rotation layer')
    if aim_fixture:
        for name,axis,limit in (('yaw','Z_Axis',45),('pitch','X_Axis',40)):
            value=terminal
            if (value['$type']!='animAnimNode_RotateBone' or value['bone']['name']!=base.cname('Spine2')
                or value['axis']!=axis or value['scale']!=1 or value['biasAngle']!=0
                or value['minAngle']!=-limit or value['maxAngle']!=limit or not value['clampRotation']
                or value['useIncrementalMode'] or not value['resetOnActivation'] or not value['inModelSpace']
                or data(value['angleNode']['node'])['variableName']!=base.cname('cp_coop_aim_'+name)
                or any(value[k]['node'] not in (None,{'HandleRefId':'-1'}) for k in ('minValueNode','maxValueNode'))):
                raise ValueError('Unsafe aim rotation')
            terminal=data(value['inputNode']['node'])
    if terminal is not overlay:raise ValueError('Upper-body layer disconnected')
    if (overlay['getDeltaMotionFromOverride'] or overlay['blendAllTracks']
        or [v['transformIndex']['name']['$value'] for v in overlay['bones']]!=list(UPPER_BONES)
        or any(v['weight']!=1 for v in overlay['bones'])):raise ValueError('Unsafe upper-body mask')
    if data(overlay['weightNode']['node'])['variableName']!=base.cname('cp_coop_weapon_weight'):
        raise ValueError('Wrong overlay weight')
    stance=data(overlay['inputNode']['node']);upper=data(overlay['overrideInputNode']['node'])
    def selector(value,name,count):
        if (value['$type']!='animAnimNode_Switch' or value['numInputs']!=count
            or len(value['inputNodes'])!=count or value['blendTime']!=0
            or data(value['weightNode']['node'])['variableName']!=base.cname(name)):
            raise ValueError('Wrong action selector')
    def blend(value,name):
        if (value['$type']!='animAnimNode_Blend2' or value['minInputValue']!=0 or value['maxInputValue']!=1
            or value['timeWarpingEnabled'] or value['syncMethod'] not in (None,{'HandleRefId':'-1'})
            or data(value['weightNode']['node'])['variableName']!=base.cname(name)):
            raise ValueError('Wrong real-time pose blend')
    def lower_mask(value,name):
        if (value['$type']!='animAnimNode_BlendOverride' or value['getDeltaMotionFromOverride']
            or value['blendAllTracks'] or value['timeWarpingEnabled'] or value['tracks']
            or value['blendTrackMode']!='AGBT_Interpolate'
            or [v['transformIndex']['name']['$value'] for v in value['bones']]!=list(LOWER_BONES)
            or any(v['weight']!=1 for v in value['bones'])
            or data(value['weightNode']['node'])['variableName']!=base.cname(name)):
            raise ValueError('Unsafe directional lower-body mask')
    blend(stance,'cp_coop_stance');blend(upper,'cp_coop_weapon_blend')
    gait=data(stance['firstInputNode']['node']);blend(gait,'cp_coop_loco_blend_weight')
    standing=data(gait['firstInputNode']['node']);departing=data(gait['secondInputNode']['node'])
    crouch=data(stance['secondInputNode']['node'])
    selector(standing,'cp_coop_loco_phase',len(base.CLIPS));blend(crouch,'cp_coop_crouch_motion')
    selector(departing,'cp_coop_loco_previous_phase',len(base.CLIPS))
    previous=data(upper['firstInputNode']['node']);current=data(upper['secondInputNode']['node'])
    selector(previous,'cp_coop_weapon_previous_pose',len(upper_clips));selector(current,'cp_coop_weapon_pose',len(upper_clips))
    if data(crouch['firstInputNode']['node'])['animation']['$value']!='cp_coop_stealth_idle_low_unarmed':
        raise ValueError('Wrong crouch animation names')
    crouch_walk=data(crouch['secondInputNode']['node'])
    crouch_clips=[crouch_walk]
    names=['cp_coop_stealth_walk_0']
    if directional_walk:
        blend(crouch_walk,'cp_coop_crouch_backward')
        crouch_clips=[data(crouch_walk[k]['node']) for k in ('firstInputNode','secondInputNode')]
        names+=['cp_coop_crouch_backward_walk_180']
    if [v['animation']['$value'] for v in crouch_clips]!=names:raise ValueError('Wrong crouch walking clips')
    for node in crouch_clips:
        if (node['$type']!='animAnimNode_SkFrameAnim' or node['isLooped']
            or data(node['progressLink']['node'])['variableName']!=base.cname('cp_coop_crouch_progress' if directional_walk else 'cp_coop_loco_progress')
            or any(node[k]['node'] not in (None,{'HandleRefId':'-1'}) for k in ('timeLink','frameLink'))):
            raise ValueError('Crouch gait must use held distance samples')
    standing_clips=list(standing['inputNodes'])
    departing_clips=list(departing['inputNodes'])
    if directional_walk:
        walking=data(standing_clips[1]['node']);lower_mask(walking,'cp_coop_walk_direction_weight')
        standing_clips[1]=walking['inputNode']
        selected=data(walking['overrideInputNode']['node']);blend(selected,'cp_coop_walk_direction_blend')
        names=tuple('cp_coop_directional_neutral_'+n for n in ('walk_0','walk_090','walk_180','walk_270'))
        for field,name,reader in (('firstInputNode','cp_coop_walk_previous_direction','cp_coop_walk_previous_progress'),
                                  ('secondInputNode','cp_coop_walk_direction','cp_coop_loco_progress')):
            switch=data(selected[field]['node']);selector(switch,name,4)
            if [data(v['node'])['animation']['$value'] for v in switch['inputNodes']]!=list(names):
                raise ValueError('Wrong directional clips')
            for value in switch['inputNodes']:
                node=data(value['node'])
                if (node['$type']!='animAnimNode_SkFrameAnim' or node['isLooped']
                    or data(node['progressLink']['node'])['variableName']!=base.cname(reader)
                    or any(node[k]['node'] not in (None,{'HandleRefId':'-1'}) for k in ('timeLink','frameLink'))):
                    raise ValueError('Directional walk must use distance samples')
        walking=data(departing_clips[1]['node']);lower_mask(walking,'cp_coop_loco_previous_direction_weight')
        departing_clips[1]=walking['inputNode']
        selected=data(walking['overrideInputNode']['node']);selector(selected,'cp_coop_loco_previous_direction',4)
        if [data(v['node'])['animation']['$value'] for v in selected['inputNodes']]!=list(names):
            raise ValueError('Wrong departing direction clips')
        for pose in selected['inputNodes']:
            node=data(pose['node'])
            if (node['$type']!='animAnimNode_SkFrameAnim' or node['isLooped']
                or data(node['progressLink']['node'])['variableName']!=base.cname('cp_coop_loco_previous_progress')
                or any(node[k]['node'] not in (None,{'HandleRefId':'-1'}) for k in ('timeLink','frameLink'))):
                raise ValueError('Departing direction must freeze the previous gait sample')
    for inputs,names in [(standing_clips,base.CLIPS),(departing_clips,base.CLIPS),
                         (previous['inputNodes'],upper_clips),(current['inputNodes'],upper_clips)]:
        if [data(link['node'])['animation']['$value'] for link in inputs]!=list(names):
            raise ValueError('Wrong animation names')
    for i,pose in enumerate(departing_clips):
        node=data(pose['node'])
        if (node['$type']!=('animAnimNode_SkAnim' if i==0 else 'animAnimNode_SkFrameAnim')
            or node['isLooped']!=int(i==0) or i and data(node['progressLink']['node'])['variableName']!=base.cname('cp_coop_loco_previous_progress')):
            raise ValueError('Departing gait must freeze its sample')
        if i and any(node[k]['node'] not in (None,{'HandleRefId':'-1'}) for k in ('timeLink','frameLink')):
            raise ValueError('Departing gait cannot use engine-time playback')
    for switch,reader in ((previous,'cp_coop_weapon_previous_progress'),(current,'cp_coop_loco_progress')):
        for pose,name in zip(switch['inputNodes'],upper_clips):
            node=data(pose['node']);sampled='walk' in name or 'sprint' in name
            if node['$type']!=('animAnimNode_SkFrameAnim' if sampled else 'animAnimNode_SkAnim'):
                raise ValueError('Weapon gait must follow distance sampling')
            if sampled and data(node['progressLink']['node'])['variableName']!=base.cname(reader):
                raise ValueError('Wrong weapon gait progress')
            if sampled and (node['isLooped'] or any(node[k]['node'] not in (None,{'HandleRefId':'-1'}) for k in ('timeLink','frameLink'))):
                raise ValueError('Weapon gait must not use engine-time playback')
    if len([v for v in definitions.values() if v.get('$type')=='animAnimNode_Blend2'])!=(6 if directional_walk else 4):
        raise ValueError('Wrong real-time blend layer count')
    nodes={k for k,v in definitions.items() if v.get('$type','').startswith('animAnimNode_')}
    init=[v.get('HandleId',v.get('HandleRefId')) for v in gr['nodesToInit']]
    if set(init)!=nodes or len(init)!=len(nodes):raise ValueError('Incomplete graph initialization')
    registered=[v.get('HandleId',v.get('HandleRefId')) for v in root['nodes']]
    if set(registered)!=nodes-{gr['rootNode'].get('HandleId',gr['rootNode'].get('HandleRefId'))} or len(registered)!=len(nodes)-1:
        raise ValueError('Incomplete root node registration')
    if gr['animFeatures'] or gr['additionalAnimDatabases'] or any(gr[k] for k in ('useAnimCommands','useAnimCommandsForCrowd','useAnimStaticCommands')):
        raise ValueError('Gameplay graph command execution forbidden')


def build(wolvenkit,output,weapon_profile='rifle',aim_fixture=False,directional_walk=False):
    if output.exists():raise ValueError('Choose a new output folder')
    if hashlib.sha256(wolvenkit.read_bytes()).hexdigest()!='7ae9c308da2fe003220b55ce4ca9c122b51f0701a67db1618cca3ff4f7ff6738':
        raise ValueError('Pinned WolvenKit required')
    entity,graph=sources(weapon_profile,aim_fixture,directional_walk);validate(entity,graph,weapon_profile,aim_fixture,directional_walk)
    output.mkdir(parents=True);stage=output/'CP2077Coop_ActionFixture';records={};logs=[]
    def run(*args):
        result=subprocess.run([str(wolvenkit),*map(str,args)],capture_output=True,text=True,encoding='utf-8',errors='replace')
        logs.append(result.stdout+result.stderr);(output/'build.log').write_text('\n'.join(logs),encoding='utf-8')
        if result.returncode:raise RuntimeError('Native fixture build failed; see build.log')
        return result.stdout
    roundtrip=output/'roundtrip';roundtrip.mkdir()
    for path,doc in ((ENTITY,entity),(GRAPH,graph)):
        dest=stage/path.replace('\\','/');dest.parent.mkdir(parents=True,exist_ok=True)
        raw=output/(dest.name+'.json');raw.write_text(json.dumps(doc),encoding='utf-8')
        run('convert','deserialize',raw,'-o',dest.parent)
        records[path]=hashlib.sha256(dest.read_bytes()).hexdigest()
        run('convert','serialize',dest,'-o',roundtrip)
    validate(json.loads((roundtrip/'player_actions_fixture.ent.json').read_text()),
             json.loads((roundtrip/'player_actions_fixture.animgraph.json').read_text()),weapon_profile,aim_fixture,directional_walk)
    packed=output/'out';packed.mkdir();run('pack',stage,'-o',packed)
    archive=packed/(stage.name+'.archive')
    if sorted(run('archive',archive,'--list').strip().splitlines())!=sorted((ENTITY,GRAPH)):
        raise ValueError('Unexpected fixture archive content')
    unpacked=output/'unpacked';unpacked.mkdir();run('unbundle',archive,'-o',unpacked)
    if any(hashlib.sha256((unpacked/path.replace('\\','/')).read_bytes()).hexdigest()!=sha for path,sha in records.items()):
        raise ValueError('Extracted fixture payload mismatch')
    manifest={'scope':'local render-only pose fixture, not synchronized actions',
        'archive':str(archive),'archive_sha256':hashlib.sha256(archive.read_bytes()).hexdigest(),
        'resources':records,'required_private_cache':list(profile_values(weapon_profile,directional_walk)[0]),'bundled_vanilla_resources':[],
        'weapon_pose_profile':weapon_profile,
        'isolated_aim_fixture':aim_fixture,
        'directional_walk':directional_walk,
        'builder_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        'visual_validation':'pending'}
    (output/'manifest.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8');print(json.dumps(manifest))


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--wolvenkit',required=True,type=Path)
    parser.add_argument('--output',required=True,type=Path)
    parser.add_argument('--weapon-profile',choices=('rifle','shotgundual'),default='rifle')
    parser.add_argument('--aim-fixture',action='store_true',help='PRIVATE isolated upper-body aim qualification only')
    parser.add_argument('--directional-walk',action='store_true',help='PRIVATE qualified armed-walk direction candidate')
    args=parser.parse_args();build(args.wolvenkit,args.output,args.weapon_profile,args.aim_fixture,args.directional_walk)
