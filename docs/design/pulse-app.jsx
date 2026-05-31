// pulse-app.jsx — Pulse Gym interactive prototype
// Loaded after React + Babel. Renders into #root.

const { useState, useEffect, useRef, Fragment } = React;

// ─────────────────────────────────────────────────────────────
// PALETTES
// ─────────────────────────────────────────────────────────────
const PALETTES = {
  coastal: {
    label: "Coastal",
    bg:"#06121F", surface:"#0E1F33", surface2:"#16314D",
    ink:"#FFF4D6", inkSoft:"rgba(255,244,214,.62)", inkFaint:"rgba(255,244,214,.16)",
    accent:"#26B6F6", accentDeep:"#0E5BA8", accent2:"#FF6A1F", onAccent:"#06121F",
  },
  mint: {
    label: "Mint",
    bg:"#0F1814", surface:"#1A2620", surface2:"#26332B",
    ink:"#E1F4E8", inkSoft:"rgba(225,244,232,.64)", inkFaint:"rgba(225,244,232,.16)",
    accent:"#00D9B8", accentDeep:"#007A6C", accent2:"#FFCC33", onAccent:"#0F1814",
  },
};

function paletteVars(p){
  return {
    "--bg":p.bg, "--surface":p.surface, "--surface-2":p.surface2,
    "--ink":p.ink, "--ink-soft":p.inkSoft, "--ink-faint":p.inkFaint,
    "--accent":p.accent, "--accent-deep":p.accentDeep, "--accent-2":p.accent2,
    "--on-accent":p.onAccent,
  };
}

// ─────────────────────────────────────────────────────────────
// ICONS
// ─────────────────────────────────────────────────────────────
const I = {
  back:  <span style={{fontFamily:'Oswald, sans-serif',fontWeight:700,fontSize:20,lineHeight:1}}>←</span>,
  fwd:   <span style={{fontFamily:'Oswald, sans-serif',fontWeight:700,fontSize:18,lineHeight:1}}>→</span>,
  plus:  <span style={{fontFamily:'Oswald, sans-serif',fontWeight:700,fontSize:22,lineHeight:1}}>+</span>,
  dots:  <span style={{fontFamily:'Hanken Grotesk, sans-serif',fontWeight:800,fontSize:18,lineHeight:1,letterSpacing:1}}>···</span>,
  chev:  <span style={{fontFamily:'Oswald, sans-serif',fontWeight:700,fontSize:15,lineHeight:1,opacity:.45}}>›</span>,
  grip:  <span style={{fontFamily:'Geist Mono, monospace',fontSize:13,opacity:.45,letterSpacing:-2}}>⋮⋮</span>,
  pause: <span style={{fontFamily:'Hanken Grotesk, sans-serif',fontWeight:800,fontSize:13,letterSpacing:-1}}>❚❚</span>,
  bolt:  <svg width="20" height="20" viewBox="0 0 24 24" fill="none"><path d="M13 2L4 14h7l-1 8 9-12h-7l1-8z" stroke="currentColor" strokeWidth="2.2" strokeLinejoin="round"/></svg>,
  lib:   <svg width="20" height="20" viewBox="0 0 24 24" fill="none"><path d="M4 6h7v14H4zM13 6h7v14h-7z" stroke="currentColor" strokeWidth="2" strokeLinejoin="round"/></svg>,
  cal:   <svg width="20" height="20" viewBox="0 0 24 24" fill="none"><rect x="3" y="5" width="18" height="16" rx="2" stroke="currentColor" strokeWidth="2"/><path d="M3 10h18M8 3v4M16 3v4" stroke="currentColor" strokeWidth="2" strokeLinecap="round"/></svg>,
  user:  <svg width="20" height="20" viewBox="0 0 24 24" fill="none"><circle cx="12" cy="8" r="4" stroke="currentColor" strokeWidth="2.2"/><path d="M3 21c0-4.4 4-8 9-8s9 3.6 9 8" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round"/></svg>,
  chart: <svg width="18" height="18" viewBox="0 0 24 24" fill="none"><path d="M4 20V10M10 20V4M16 20v-7M22 20H2" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round"/></svg>,
};

// ─────────────────────────────────────────────────────────────
// DATA
// ─────────────────────────────────────────────────────────────
// set types: working | warmup | amrap | failure
// A WorkoutExercise = (name, variation, target sets). Superset groups share `ss`.
const TODAY_WORKOUT = {
  id:"chest-tris", name:"Chest & Tris", focus:"PUSH", day:23, week:4,
  est:"~60 min",
  exercises:[
    { id:"flat", name:"Flat Machine Chest Press", group:"Chest", variation:"D-bar", cue:"Elbows tucked, control the eccentric. 1s pause at bottom.",
      sets:[{type:"warmup",reps:12,wt:90},{type:"working",reps:15,wt:120},{type:"working",reps:12,wt:130},{type:"working",reps:10,wt:140},{type:"working",reps:8,wt:150}] },
    { id:"incline", name:"Incline DB Press", group:"Chest", variation:null, cue:"30° bench. Don't clank the dumbbells.",
      sets:[{type:"working",reps:15,wt:55},{type:"working",reps:12,wt:60},{type:"working",reps:10,wt:65},{type:"working",reps:8,wt:70}] },
    { id:"closegrip", name:"Close Grip DB Press", group:"Chest", variation:null, cue:null,
      sets:[{type:"working",reps:12,wt:55},{type:"working",reps:10,wt:60},{type:"working",reps:8,wt:65}] },
    // superset A+B (group "ss1")
    { id:"tri-cable", name:"Tricep Cable Ext.", group:"Triceps", variation:"Rope", ss:"ss1", ssLabel:"4A", cue:"Lock elbows to your sides.",
      sets:[{type:"working",reps:12,wt:50},{type:"working",reps:12,wt:50},{type:"working",reps:12,wt:50}] },
    { id:"lat-raise", name:"Single Arm Lateral Raise", group:"Delts", variation:"Cable", ss:"ss1", ssLabel:"4B", cue:"Lead with the elbow. Left then right.",
      sets:[{type:"working",reps:12,wt:15},{type:"working",reps:12,wt:15},{type:"working",reps:12,wt:15}] },
    { id:"shoulder", name:"Shoulder Press Machine", group:"Delts", variation:null, cue:null,
      sets:[{type:"working",reps:12,wt:70},{type:"working",reps:10,wt:80},{type:"working",reps:8,wt:90},{type:"working",reps:6,wt:100}] },
    { id:"plate-tri", name:"Plate Tricep Extension", group:"Triceps", variation:null, cue:null,
      sets:[{type:"working",reps:12,wt:70},{type:"working",reps:12,wt:70},{type:"working",reps:12,wt:70}] },
    { id:"pushup", name:"Tricep Push Up", group:"Triceps", variation:null, cue:"Go to failure. No shame in knees.", finisher:true,
      sets:[{type:"failure",reps:null,wt:0}] },
  ],
};

const RECENT = [
  {dy:"TUE", d:"YESTERDAY", name:"Legs", sub:"71m · 18.7k LBS", pr:true},
  {dy:"MON", d:"MAY 26", name:"Back & Bis", sub:"62m · 14.2k LBS"},
  {dy:"FRI", d:"MAY 23", name:"Arms", sub:"45m · 8.4k LBS"},
  {dy:"THU", d:"MAY 22", name:"Shoulders", sub:"55m · 11.8k LBS"},
  {dy:"WED", d:"MAY 21", name:"Chest & Tris", sub:"58m · 12.4k LBS", pr:true},
];

const LIBRARY_FOLDERS = [
  {id:"ppl", name:"Push / Pull / Legs", sub:"6 workouts · active program", color:"var(--accent)", program:true},
  {id:"cardio", name:"Cardio & Conditioning", sub:"4 workouts", color:"var(--accent-2)"},
  {id:"oneoffs", name:"One-offs", sub:"7 workouts", color:"var(--ink-faint)"},
];

const PPL_WORKOUTS = [
  {name:"Chest & Tris", sub:"7 exercises · ~60m"},
  {name:"Back & Bis", sub:"6 exercises · ~62m"},
  {name:"Legs", sub:"5 exercises · ~71m"},
  {name:"Shoulders", sub:"5 exercises · ~55m"},
  {name:"Arms · finisher", sub:"4 exercises · ~45m"},
  {name:"Active recovery", sub:"3 exercises · ~30m"},
];

const PRS = [
  {n:"Bench press", w:"275", r:"×1", m:"CHEST", d:"3d ago", fresh:true, hero:true},
  {n:"Squat", w:"365", r:"×1", m:"BACK", d:"3w ago"},
  {n:"Deadlift", w:"415", r:"×1", m:"BACK", d:"last week", fresh:true},
  {n:"OHP", w:"165", r:"×3", m:"DELTS", d:"6w ago"},
  {n:"Pulldown", w:"175", r:"×8", m:"BACK", d:"3w ago"},
  {n:"Incline DB", w:"75", r:"×8", m:"CHEST", d:"5d ago", fresh:true},
];

const WEEK = [
  {d:"M", label:"Chest & Tris", state:"done", time:"58m", vol:"12.4k"},
  {d:"T", label:"Back & Bis", state:"done", time:"62m", vol:"14.2k"},
  {d:"W", label:"Legs", state:"done", time:"71m", vol:"18.7k"},
  {d:"T", label:"Shoulders", state:"today"},
  {d:"F", label:"Arms · finisher", state:"plan"},
  {d:"S", label:"Rest", state:"rest"},
  {d:"S", label:"Rest", state:"rest"},
];

// ─────────────────────────────────────────────────────────────
// STEPS — flatten workout into an ordered step list.
// Supersets interleave A1→B1→A2→B2; rest only after the last
// member of each round, and never after the final step.
// Each step: { exIdx, setIdx, rest, ssPartnerExIdx|null }
// ─────────────────────────────────────────────────────────────
function buildSteps(workout){
  const ex = workout.exercises;
  const steps = [];
  let i = 0;
  while (i < ex.length){
    if (ex[i].ss){
      // collect consecutive members sharing this ss group
      const grp = ex[i].ss;
      const members = [];
      let j = i;
      while (j < ex.length && ex[j].ss === grp){ members.push(j); j++; }
      const rounds = Math.max(...members.map(m => ex[m].sets.length));
      for (let r = 0; r < rounds; r++){
        members.forEach((mIdx, k) => {
          if (r < ex[mIdx].sets.length){
            const isLastMemberOfRound = k === members.length - 1;
            steps.push({
              exIdx: mIdx, setIdx: r,
              rest: isLastMemberOfRound,           // rest only after the round's last member
              ssPartnerExIdx: members.find(x => x !== mIdx) ?? null,
            });
          }
        });
      }
      i = j;
    } else {
      const sets = ex[i].sets;
      for (let s = 0; s < sets.length; s++){
        steps.push({ exIdx: i, setIdx: s, rest: true, ssPartnerExIdx: null });
      }
      i++;
    }
  }
  // never rest after the final step
  if (steps.length) steps[steps.length-1].rest = false;
  return steps;
}
const STEPS = buildSteps(TODAY_WORKOUT);

// exercise index -> list of its step indices (for jump + done tracking)
const EX_STEPS = {};
STEPS.forEach((s, idx) => { if(!EX_STEPS[s.exIdx]) EX_STEPS[s.exIdx] = []; EX_STEPS[s.exIdx].push(idx); });

// Alternatives offered when swapping (by muscle group)
const ALTERNATIVES = {
  Chest:   [{name:"Barbell Bench Press",equip:"BARBELL"},{name:"Pec Deck",equip:"MACHINE"},{name:"Cable Fly",equip:"CABLE"},{name:"Push Up",equip:"BODYWEIGHT"}],
  Triceps: [{name:"Overhead Cable Extension",equip:"CABLE"},{name:"Skullcrusher",equip:"BARBELL"},{name:"Bench Dip",equip:"BODYWEIGHT"}],
  Delts:   [{name:"DB Lateral Raise",equip:"DUMBBELL"},{name:"Machine Lateral Raise",equip:"MACHINE"},{name:"Cable Y-Raise",equip:"CABLE"}],
};

// Related exercises (same group) for the history sheet
const RELATED = {
  Chest:   [["Incline DB Press","60 lb × 8","5d ago"],["Cable Fly","40 lb × 12","5d ago"]],
  Triceps: [["Plate Tricep Ext","70 lb × 12","today"],["Close Grip DB","65 lb × 8","today"]],
  Delts:   [["Shoulder Press","100 lb × 6","today"],["Rear Delt Fly","30 lb × 15","5d ago"]],
};

// Build plausible prior-session history for an exercise from its prescription
function getHistory(ex){
  const working = ex.sets.filter(s => s.type !== "warmup");
  const line = working.map(s => s.reps).join("·");
  const topWt = Math.max(...working.map(s => s.wt), 0);
  const dates = ["FRI · MAY 23","MON · MAY 19","FRI · MAY 16","MON · MAY 12"];
  return dates.map((d,i) => {
    const wt = Math.max(0, topWt - i*5);
    const vol = working.reduce((a,s)=>a + (s.reps||0)*wt, 0);
    return { d, line, top: wt ? `${wt} lb` : "bodyweight", vol: vol ? `${(vol/1000).toFixed(1)}k` : "—" };
  });
}

// ─────────────────────────────────────────────────────────────
// PRIMITIVES
// ─────────────────────────────────────────────────────────────
function Eyebrow({children, style}){
  return <div className="eyebrow" style={style}>{children}</div>;
}

function Btn({children, kind="primary", size="md", onClick, style, ...rest}){
  return <button type="button" className={`btn ${kind} ${size}`} onClick={onClick} style={style} {...rest}>{children}</button>;
}

function IconBtn({children, onClick, style}){
  return <button type="button" className="icon-btn" onClick={onClick} style={style}>{children}</button>;
}

function Lockup({num, top, bot, size=120, numColor="var(--on-accent)", topColor="var(--accent-2)", botColor}){
  return (
    <div className="lockup" style={{fontSize:size}}>
      <div className="num" style={{color:numColor}}>{num}</div>
      <div className="lbl-top" style={{color:topColor}}>{top}</div>
      <div className="lbl-bot" style={{color:botColor||numColor}}>{bot}</div>
    </div>
  );
}

function TopBar({onBack, eyebrow, right, onRight}){
  return (
    <div className="topbar">
      {onBack ? <IconBtn onClick={onBack}>{I.back}</IconBtn> : <div style={{width:36}}></div>}
      {eyebrow && <Eyebrow>{eyebrow}</Eyebrow>}
      {right ? <IconBtn onClick={onRight}>{right}</IconBtn> : <div style={{width:36}}></div>}
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// TODAY
// ─────────────────────────────────────────────────────────────
function TodayScreen({ onStartWorkout, go }){
  const done = WEEK.filter(w=>w.state==="done").length;
  const planned = WEEK.filter(w=>w.state!=="rest").length;
  return (
    <div className="body">
      <TopBar eyebrow="WED · MAY 28" right={I.dots} />
      <div style={{display:"flex",alignItems:"baseline",justifyContent:"space-between"}}>
        <h1 className="h1">Hey, Alex.</h1>
        <div style={{fontFamily:'Oswald, sans-serif',fontWeight:700,fontSize:26,color:"var(--accent-2)",letterSpacing:"-.01em",lineHeight:.85}}>27<span style={{fontFamily:'Hanken Grotesk, sans-serif',fontSize:10,marginLeft:3,opacity:.7,fontWeight:700,letterSpacing:".06em"}}>D</span></div>
      </div>

      <div className="scroll">
        {/* Hero workout */}
        <div className="card accent" style={{padding:"18px 18px 20px"}}>
          <Eyebrow style={{opacity:.85}}>TODAY · PPL · WEEK 4</Eyebrow>
          <Lockup num="7" top="Day 23" bot={<span>Chest<br/>& Tris.</span>} size={116} />
          <div style={{display:"flex",justifyContent:"space-between",alignItems:"flex-end",marginTop:14}}>
            <Eyebrow style={{opacity:.85}}>7 EXERCISES · ~60M</Eyebrow>
            <Btn size="sm" onClick={onStartWorkout} style={{background:"var(--ink)",color:"var(--bg)",border:"2px solid var(--ink)"}}>Start {I.fwd}</Btn>
          </div>
        </div>

        {/* Week strip */}
        <div style={{display:"flex",justifyContent:"space-between",alignItems:"baseline",marginTop:16,marginBottom:8}}>
          <Eyebrow>THIS WEEK</Eyebrow>
          <Eyebrow>{done} OF {planned} DONE</Eyebrow>
        </div>
        <div style={{display:"flex",gap:4}}>
          {WEEK.map((w,i) => (
            <div key={i} style={{
              flex:1,aspectRatio:.82,display:"flex",alignItems:"center",justifyContent:"center",
              borderRadius:8,fontFamily:'Geist Mono, monospace',fontSize:11,fontWeight:600,letterSpacing:".08em",
              background:w.state==="done"?"var(--accent)":"transparent",
              color:w.state==="done"?"var(--on-accent)":"var(--ink)",
              border:w.state==="today"?"2px solid var(--accent-2)":w.state==="rest"?"1px dashed var(--ink-faint)":w.state==="done"?"1.5px solid var(--accent)":"1.5px solid var(--ink-faint)",
              opacity:w.state==="rest"?.4:1,
            }}>{w.d}</div>
          ))}
        </div>

        {/* Recent */}
        <Eyebrow style={{marginTop:16,marginBottom:8}}>YESTERDAY</Eyebrow>
        <div className="row" onClick={()=>go("session-detail")} style={{cursor:"pointer",opacity:.85}}>
          <div className="nm"><div className="nm-name">Legs</div><div className="nm-sub">71M · 18.7K LBS · +1 PR</div></div>
          <span>{I.chev}</span>
        </div>
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// PRE-WORKOUT
// ─────────────────────────────────────────────────────────────
function PreworkoutScreen({ onStart, onBack }){
  const w = TODAY_WORKOUT;
  // group consecutive supersets for display
  const rows = [];
  w.exercises.forEach((ex) => {
    if (ex.ss){
      const last = rows[rows.length-1];
      if (last && last.ss === ex.ss){ last.items.push(ex); return; }
      rows.push({ ss:ex.ss, items:[ex] });
    } else {
      rows.push({ ex });
    }
  });
  return (
    <div className="body">
      <TopBar onBack={onBack} eyebrow="PUSH · WEEK 4" right={I.dots} />
      <h1 className="h1" style={{fontSize:40}}>{w.name}.</h1>
      <div className="sub">Heavy day. Pyramid reps, last move to failure.</div>

      <div style={{display:"flex",gap:6,marginTop:14,marginBottom:6,flexWrap:"wrap"}}>
        <Chip>{w.exercises.length} EXERCISES</Chip>
        <Chip accent2>{w.est}</Chip>
        <Chip accent>PYRAMID</Chip>
      </div>

      <Eyebrow style={{marginTop:10,marginBottom:8}}>THE PLAN</Eyebrow>
      <div className="scroll" style={{gap:8}}>
        {rows.map((r,i) => {
          if (r.ss){
            return (
              <div key={i} className="row" style={{flexDirection:"column",alignItems:"stretch",gap:8,borderColor:"var(--accent-2)"}}>
                <div style={{display:"flex",alignItems:"center",gap:10}}>
                  <div className="badge" style={{background:"var(--accent-2)",color:"var(--on-accent)",borderColor:"var(--accent-2)"}}>SS</div>
                  <div className="nm"><div className="nm-sub" style={{color:"var(--accent-2)",fontWeight:600}}>SUPERSET · {r.items[0].sets.length} ROUNDS</div></div>
                </div>
                {r.items.map((ex,j) => (
                  <div key={j} style={{display:"flex",alignItems:"baseline",gap:10,paddingLeft:38}}>
                    <span style={{fontFamily:'Geist Mono, monospace',fontWeight:600,fontSize:11,color:"var(--accent-2)",minWidth:20}}>{ex.ssLabel}</span>
                    <span style={{flex:1,fontFamily:'Hanken Grotesk, sans-serif',fontWeight:600,fontSize:13,color:"var(--ink)"}}>{exTitle(ex)}</span>
                  </div>
                ))}
              </div>
            );
          }
          const ex = r.ex;
          return (
            <div key={i} className="row">
              <div className="badge">{i+1}</div>
              <div className="nm"><div className="nm-name">{exTitle(ex)}</div><div className="nm-sub">{setSummary(ex)}</div></div>
              <div className="end">{ex.sets.length}<span className="end-unit">{ex.sets.length===1?"set":"sets"}</span></div>
            </div>
          );
        })}
      </div>

      <div style={{padding:"12px 0 18px"}}>
        <Btn size="lg" onClick={onStart} style={{width:"100%"}}>Start session {I.fwd}</Btn>
      </div>
    </div>
  );
}

function Chip({children, accent, accent2}){
  const st = accent
    ? {background:"var(--accent)",color:"var(--on-accent)",border:"1.5px solid var(--ink)"}
    : accent2
    ? {background:"var(--accent-2)",color:"var(--on-accent)",border:"1.5px solid var(--ink)"}
    : {border:"1.5px solid var(--ink)",color:"var(--ink)"};
  return <span style={{padding:"6px 12px",borderRadius:999,fontFamily:'Geist Mono, monospace',fontSize:10,letterSpacing:".14em",textTransform:"uppercase",fontWeight:accent||accent2?600:500,...st}}>{children}</span>;
}

function exTitle(ex){ return ex.variation ? `${ex.name} · ${ex.variation}` : ex.name; }
function setSummary(ex){
  if (ex.finisher) return "To failure · bodyweight";
  const working = ex.sets.filter(s=>s.type!=="warmup");
  return working.map(s=>s.reps).join("-") + " reps";
}

// ─────────────────────────────────────────────────────────────
// ACTIVE SESSION (drives both single + superset)
// ─────────────────────────────────────────────────────────────
function ActiveScreen({ step, isFinal, swaps, doneSteps, onLogSet, onSkip, onPause, onOpenSheet }){
  const { exIdx, setIdx } = step;
  const w = TODAY_WORKOUT;
  const ex = w.exercises[exIdx];
  const set = ex.sets[setIdx];
  const isSuperset = !!ex.ss;

  // superset partner (other member of the pair)
  const partner = step.ssPartnerExIdx != null ? w.exercises[step.ssPartnerExIdx] : null;

  const [reps, setReps] = useState(set.reps);
  const [wt, setWt] = useState(set.wt);
  useEffect(()=>{ setReps(set.reps); setWt(set.wt); }, [exIdx, setIdx]);

  // session swap override
  const swap = swaps[exIdx] || null;
  const shownName = swap ? swap.name : ex.name;
  const shownVariation = swap ? null : ex.variation;

  const totalSets = ex.sets.length;
  const setTypeLabel = {working:"WORKING", warmup:"WARMUP", amrap:"AMRAP", failure:"FAILURE"}[set.type];
  // if this step doesn't rest after, the next thing is the superset partner
  const goesToPartner = isSuperset && !step.rest && partner;
  const logLabel = isFinal ? "Finish workout" : goesToPartner ? `Log → ${partner.ssLabel}` : "Log set";

  return (
    <div className="body">
      <TopBar onBack={onPause} eyebrow={`EX ${exIdx+1} / ${w.exercises.length}${isSuperset?` · ${ex.ssLabel}`:""}`} right={I.plus} />

      {/* progress segments — rounds for a superset, sets otherwise */}
      <div style={{display:"flex",gap:4,marginTop:4}}>
        {ex.sets.map((_,i) => (
          <div key={i} style={{
            flex:1,height:6,borderRadius:6,boxSizing:"border-box",
            background: i<setIdx ? "var(--accent)" : i===setIdx ? "var(--accent-2)" : "var(--ink-faint)",
            opacity: i>setIdx ? .5 : 1,
            border: i===setIdx ? "2px solid var(--ink)" : "0",
          }}></div>
        ))}
      </div>

      {/* exercise meta + variation */}
      <div style={{display:"flex",alignItems:"flex-end",justifyContent:"space-between",gap:10,marginTop:12}}>
        <div>
          <Eyebrow style={{fontSize:10}}>{ex.group.toUpperCase()}{isSuperset?` · ${ex.ssLabel}`:""}{swap?" · SWAPPED":""}</Eyebrow>
          <h1 className="h1" style={{fontSize:23,marginTop:2,lineHeight:.98}}>{shownName}.</h1>
        </div>
        {shownVariation && (
          <div onClick={()=>onOpenSheet("swap")} style={{cursor:"pointer",padding:"4px 10px",borderRadius:999,background:"var(--accent)",color:"var(--on-accent)",fontFamily:'Geist Mono, monospace',fontSize:9,fontWeight:600,letterSpacing:".12em",textTransform:"uppercase",whiteSpace:"nowrap"}}>{shownVariation} ⇆</div>
        )}
      </div>

      {/* action row — swap / history / jump */}
      <div style={{display:"flex",gap:6,marginTop:10}}>
        <ActChip onClick={()=>onOpenSheet("swap")}>⇆ Swap</ActChip>
        <ActChip onClick={()=>onOpenSheet("history")}>↻ History</ActChip>
        <ActChip onClick={()=>onOpenSheet("jump")}>☰ Jump</ActChip>
      </div>

      {/* cue */}
      {ex.cue && (
        <div style={{padding:"8px 12px",borderRadius:10,background:"var(--ink-faint)",marginTop:10,display:"flex",alignItems:"flex-start",gap:8}}>
          <span style={{fontFamily:'Oswald, sans-serif',fontWeight:700,fontSize:14,color:"var(--accent-2)",lineHeight:1.2}}>!</span>
          <span style={{fontFamily:'Hanken Grotesk, sans-serif',fontSize:12,color:"var(--ink-soft)",fontWeight:500,lineHeight:1.3}}>{ex.cue}</span>
        </div>
      )}

      {/* hero set card */}
      <div className="card accent" style={{marginTop:12,padding:"16px 18px 20px"}}>
        <div style={{display:"flex",justifyContent:"space-between",alignItems:"flex-start"}}>
          <div style={{padding:"2px 8px",borderRadius:999,background:set.type==="working"?"var(--on-accent)":"transparent",color:set.type==="working"?"var(--accent)":"var(--on-accent)",border:set.type==="working"?"0":"1.5px solid rgba(255,255,255,.4)",fontFamily:'Geist Mono, monospace',fontSize:9,fontWeight:600,letterSpacing:".14em",textTransform:"uppercase"}}>{setTypeLabel}</div>
          <Eyebrow style={{opacity:.85}}>SET {setIdx+1} / {totalSets}</Eyebrow>
        </div>

        {set.type==="failure" ? (
          <Lockup num="∞" top="To failure" topColor="var(--on-accent)" bot={<span>Max<br/>reps.</span>} size={120} />
        ) : (
          <Lockup num={reps} top={`Set ${setIdx+1}`} topColor="var(--on-accent)" bot={<span>Reps<br/>@ {wt}.</span>} size={124} />
        )}

        <div style={{display:"flex",justifyContent:"space-between",alignItems:"center",marginTop:12}}>
          <Eyebrow style={{opacity:.85}}>{set.type==="failure" ? "BODYWEIGHT" : `${wt} LBS · ${reps} REPS`}</Eyebrow>
          <Eyebrow style={{color:"var(--on-accent)",fontWeight:600}}>{(()=>{
            const working = ex.sets.map((s,i)=>({reps:s.reps,i})).filter(s=>ex.sets[s.i].type!=="warmup");
            return working.map((s,k)=>(
              <span key={k}>
                <span style={{borderBottom:s.i===setIdx?"2px solid var(--accent-2)":"2px solid transparent",paddingBottom:1}}>{s.reps}</span>
                {k<working.length-1 ? <span style={{opacity:.5}}> → </span> : null}
              </span>
            ));
          })()}</Eyebrow>
        </div>
      </div>

      {/* steppers (hide on failure) */}
      {set.type!=="failure" && (
        <div style={{display:"flex",gap:8,marginTop:12}}>
          <Stepper label="WEIGHT" value={wt} unit="lb" onDec={()=>setWt(Math.max(0,wt-5))} onInc={()=>setWt(wt+5)} />
          <Stepper label="REPS" value={reps} onDec={()=>setReps(Math.max(0,reps-1))} onInc={()=>setReps(reps+1)} accent />
        </div>
      )}

      {/* superset partner peek — same round */}
      {isSuperset && partner && (
        <div style={{marginTop:10,display:"flex",alignItems:"center",gap:10,padding:"10px 14px",borderRadius:14,border:"2px solid var(--accent-2)",opacity:.85}}>
          <div style={{fontFamily:'Oswald, sans-serif',fontWeight:700,fontSize:22,color:"var(--accent-2)",letterSpacing:"-.01em"}}>{partner.ssLabel}</div>
          <div style={{flex:1,minWidth:0}}>
            <div style={{fontFamily:'Hanken Grotesk, sans-serif',fontWeight:700,fontSize:13,color:"var(--ink)",overflow:"hidden",textOverflow:"ellipsis",whiteSpace:"nowrap"}}>{partner.name}</div>
            <Eyebrow style={{fontSize:9}}>{goesToPartner ? "NEXT IN PAIR" : "PAIRED"} · {(partner.sets[setIdx]||partner.sets[0]).reps} REPS · {(partner.sets[setIdx]||partner.sets[0]).wt} LB</Eyebrow>
          </div>
        </div>
      )}

      <div style={{flex:1}}></div>

      <div style={{display:"flex",gap:8,padding:"8px 0 18px"}}>
        <Btn kind="secondary" size="sm" onClick={onSkip}>Skip</Btn>
        <Btn size="lg" onClick={()=>onLogSet({reps,wt})} style={{flex:1}}>{logLabel} {I.fwd}</Btn>
      </div>
    </div>
  );
}

function ActChip({children, onClick}){
  return <button type="button" onClick={onClick} style={{flex:1,appearance:"none",cursor:"pointer",background:"transparent",border:"1.5px solid var(--ink-faint)",borderRadius:999,padding:"8px 6px",color:"var(--ink)",fontFamily:'Geist Mono, monospace',fontSize:10,fontWeight:600,letterSpacing:".08em",textTransform:"uppercase"}}>{children}</button>;
}

function Stepper({label, value, unit, onDec, onInc, accent}){
  return (
    <div style={{flex:1,display:"flex",alignItems:"center",gap:8,padding:"8px 10px",borderRadius:12,border:`1.5px solid ${accent?"var(--accent)":"var(--ink-faint)"}`}}>
      <IconBtn onClick={onDec} style={{width:32,height:32,fontSize:18}}>−</IconBtn>
      <div style={{flex:1,textAlign:"center"}}>
        <Eyebrow style={{fontSize:9,color:accent?"var(--accent)":"var(--ink-soft)"}}>{label}</Eyebrow>
        <div style={{fontFamily:'Oswald, sans-serif',fontWeight:700,fontSize:26,letterSpacing:"-.01em",lineHeight:.9,color:accent?"var(--accent)":"var(--ink)"}}>{value}{unit&&<span style={{fontFamily:'Hanken Grotesk, sans-serif',fontSize:10,marginLeft:2,opacity:.6}}>{unit}</span>}</div>
      </div>
      <IconBtn onClick={onInc} style={{width:32,height:32,fontSize:18}}>+</IconBtn>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// SHEETS (swap / history / jump) — overlay the active screen
// ─────────────────────────────────────────────────────────────
function Sheet({ title, eyebrow, onClose, children }){
  return (
    <div className="sheet-wrap">
      <div className="sheet-dim" onClick={onClose}></div>
      <div className="sheet">
        <div className="sheet-handle"></div>
        <div style={{display:"flex",justifyContent:"space-between",alignItems:"flex-start",marginBottom:4}}>
          <div>
            {eyebrow && <Eyebrow style={{marginBottom:2}}>{eyebrow}</Eyebrow>}
            <h1 className="h1" style={{fontSize:26}}>{title}</h1>
          </div>
          <IconBtn onClick={onClose} style={{fontSize:15}}>✕</IconBtn>
        </div>
        {children}
      </div>
    </div>
  );
}

function SwapSheet({ ex, onPick, onClose }){
  const alts = ALTERNATIVES[ex.group] || [];
  return (
    <Sheet eyebrow={`SWAP · ${ex.group.toUpperCase()}`} title="Swap exercise." onClose={onClose}>
      <div className="sub" style={{marginBottom:10}}>No machine free? Pick an alternative — same sets &amp; reps, just this session.</div>
      <div className="sheet-scroll">
        <div className="row" style={{borderColor:"var(--accent)",borderWidth:2,marginBottom:8}}>
          <div className="nm"><div className="nm-name">{ex.name}</div><div className="nm-sub">CURRENT</div></div>
          <div style={{padding:"2px 8px",borderRadius:999,background:"var(--accent)",color:"var(--on-accent)",fontFamily:'Geist Mono, monospace',fontSize:9,fontWeight:600,letterSpacing:".12em"}}>NOW</div>
        </div>
        {alts.map((a,i) => (
          <div key={i} className="row" onClick={()=>onPick(a)} style={{cursor:"pointer",marginBottom:6}}>
            <div className="nm"><div className="nm-name">{a.name}</div><div className="nm-sub">{a.equip}</div></div>
            <span style={{fontFamily:'Oswald, sans-serif',fontWeight:700,fontSize:20,color:"var(--accent)"}}>⇆</span>
          </div>
        ))}
      </div>
    </Sheet>
  );
}

// Build a generic 4-session history from a top-weight + rep line (for related lifts)
function synthHistory(topWt, repLine){
  const dates = ["FRI · MAY 23","MON · MAY 19","FRI · MAY 16","MON · MAY 12"];
  const reps = repLine.split("·").map(n=>parseInt(n)||0);
  return dates.map((d,i) => {
    const wt = Math.max(0, topWt - i*5);
    const vol = reps.reduce((a,r)=>a + r*wt, 0);
    return { d, line:repLine, top: wt?`${wt} lb`:"bodyweight", vol: vol?`${(vol/1000).toFixed(1)}k`:"—" };
  });
}

function HistorySheet({ ex, onClose }){
  // Tab 0 = current exercise; following tabs = related lifts in same group
  const related = RELATED[ex.group] || [];
  const tabs = [
    { name: ex.name, short: shortName(ex.name), hist: getHistory(ex) },
    ...related.map(([n,top,d]) => {
      const wt = parseInt(top) || 0;
      const repLine = (top.match(/×\s*(\d+)/) ? top.match(/×\s*(\d+)/)[1] : "10") ;
      return { name:n, short:shortName(n), hist: synthHistory(wt, `${repLine}·${repLine}·${repLine}`) };
    }),
  ];
  const [active, setActive] = useState(0);
  const t = tabs[active];
  const maxVol = Math.max(...t.hist.map(h=>parseFloat(h.vol)||0), 1);

  return (
    <Sheet eyebrow={`HISTORY · ${ex.group.toUpperCase()}`} title="Past sets." onClose={onClose}>
      {/* per-exercise tabs */}
      <div style={{display:"flex",gap:6,overflowX:"auto",paddingBottom:2,marginBottom:10}}>
        {tabs.map((tb,i) => (
          <div key={i} onClick={()=>setActive(i)} style={{
            cursor:"pointer",padding:"7px 12px",borderRadius:999,whiteSpace:"nowrap",flexShrink:0,
            border:"1.5px solid "+(active===i?"var(--accent)":"var(--ink-faint)"),
            background:active===i?"var(--accent)":"transparent",
            color:active===i?"var(--on-accent)":"var(--ink-soft)",
            fontFamily:'Geist Mono, monospace',fontSize:10,fontWeight:600,letterSpacing:".1em",textTransform:"uppercase",
          }}>{i===0?"This lift":tb.short}</div>
        ))}
      </div>

      <div className="sheet-scroll">
        <div style={{fontFamily:'Hanken Grotesk, sans-serif',fontWeight:800,fontSize:18,letterSpacing:"-.02em",color:"var(--ink)",marginBottom:8}}>{t.name}</div>

        {/* mini volume chart */}
        <div style={{display:"flex",alignItems:"flex-end",gap:6,height:54,marginBottom:12}}>
          {[...t.hist].reverse().map((h,i) => {
            const v = parseFloat(h.vol)||0;
            const isLast = i === t.hist.length-1;
            return (
              <div key={i} style={{flex:1,display:"flex",flexDirection:"column",alignItems:"center",gap:4}}>
                <div style={{width:"100%",height:`${Math.max(8, v/maxVol*44)}px`,background:isLast?"var(--accent-2)":"var(--accent)",opacity:isLast?1:.55,borderRadius:"3px 3px 0 0"}}></div>
              </div>
            );
          })}
        </div>

        <Eyebrow style={{marginBottom:6}}>LAST 4 SESSIONS</Eyebrow>
        {t.hist.map((h,i) => (
          <div key={i} className="row" style={{marginBottom:6,borderColor:i===0?"var(--accent)":"var(--ink-faint)",borderWidth:i===0?2:1.5}}>
            <div className="nm"><div className="nm-name" style={{fontSize:13}}>{h.d}</div><div className="nm-sub">{h.line} REPS</div></div>
            <div style={{textAlign:"right"}}>
              <div style={{fontFamily:'Oswald, sans-serif',fontWeight:700,fontSize:18,color:i===0?"var(--accent)":"var(--ink)",letterSpacing:"-.01em",lineHeight:.9}}>{h.top}</div>
              <div className="nm-sub">{h.vol} VOL</div>
            </div>
          </div>
        ))}
      </div>
    </Sheet>
  );
}

function shortName(n){
  // first 2 words, trimmed
  return n.split(" ").slice(0,2).join(" ");
}

function JumpSheet({ curExIdx, doneSteps, swaps, onJump, onClose }){
  const w = TODAY_WORKOUT;
  return (
    <Sheet eyebrow="REORDER · DO ANY ORDER" title="Jump to exercise." onClose={onClose}>
      <div className="sub" style={{marginBottom:10}}>Machine taken? Tap any exercise to do it now — come back to the rest after.</div>
      <div className="sheet-scroll">
        {w.exercises.map((ex,i) => {
          const stepIdxs = EX_STEPS[i] || [];
          const doneCount = stepIdxs.filter(s => doneSteps.includes(s)).length;
          const allDone = doneCount === stepIdxs.length;
          const isCur = i === curExIdx;
          const nm = swaps[i] ? swaps[i].name : ex.name;
          return (
            <div key={i} className="row" onClick={()=>onJump(i)} style={{cursor:"pointer",marginBottom:6,borderColor:isCur?"var(--accent)":"var(--ink-faint)",borderWidth:isCur?2:1.5,opacity:allDone?.5:1}}>
              <div className="badge" style={allDone?{background:"var(--ink)",color:"var(--bg)",borderColor:"var(--ink)"}:isCur?{background:"var(--accent)",color:"var(--on-accent)",borderColor:"var(--accent)"}:{}}>{ex.ss?ex.ssLabel:i+1}</div>
              <div className="nm"><div className="nm-name">{nm}</div><div className="nm-sub">{allDone?`DONE · ${stepIdxs.length} SETS`:`${doneCount}/${stepIdxs.length} SETS${isCur?" · CURRENT":""}`}</div></div>
              <span className="end" style={{color:isCur?"var(--accent)":"var(--ink)"}}>{allDone?"✓":isCur?"•":"→"}</span>
            </div>
          );
        })}
      </div>
    </Sheet>
  );
}

// ─────────────────────────────────────────────────────────────
// REST TIMER
// ─────────────────────────────────────────────────────────────
function RestScreen({ nextExIdx, nextSetIdx, onDone }){
  const TOTAL = 90;
  const [t, setT] = useState(TOTAL);
  useEffect(()=>{
    if (t<=0){ onDone(); return; }
    const id = setTimeout(()=>setT(t-1), 1000);
    return ()=>clearTimeout(id);
  }, [t]);

  const w = TODAY_WORKOUT;
  const nextEx = nextExIdx != null ? w.exercises[nextExIdx] : null;
  const nextSet = nextEx ? nextEx.sets[nextSetIdx] : null;

  const C = 2*Math.PI*90;
  const pct = t/TOTAL;
  const mm = Math.floor(t/60), ss = String(t%60).padStart(2,"0");

  return (
    <div className="body">
      <TopBar eyebrow="REST · BREATHE" right={I.fwd} onRight={onDone} />
      <div style={{display:"flex",alignItems:"baseline",justifyContent:"space-between"}}>
        <h1 className="h1" style={{fontSize:34}}>Rest.</h1>
        {nextEx && <Eyebrow>{nextEx.ss?nextEx.ssLabel:`SET ${nextSetIdx+1}`}</Eyebrow>}
      </div>

      <div style={{flex:1,display:"flex",alignItems:"center",justifyContent:"center"}}>
        <div style={{position:"relative",width:220,height:220}}>
          <svg width="220" height="220" style={{transform:"rotate(-90deg)"}}>
            <circle cx="110" cy="110" r="90" fill="none" stroke="var(--ink-faint)" strokeWidth="7"/>
            <circle cx="110" cy="110" r="90" fill="none" stroke="var(--accent-2)" strokeWidth="9" strokeLinecap="round" strokeDasharray={C} strokeDashoffset={C*(1-pct)} style={{transition:"stroke-dashoffset 1s linear"}}/>
          </svg>
          <div style={{position:"absolute",inset:0,display:"flex",flexDirection:"column",alignItems:"center",justifyContent:"center"}}>
            <span style={{fontFamily:'Oswald, sans-serif',fontWeight:700,fontSize:64,letterSpacing:"-.02em",lineHeight:.85,color:"var(--accent-2)"}}>{mm}:{ss}</span>
            <Eyebrow style={{marginTop:4}}>OF 1:30</Eyebrow>
          </div>
        </div>
      </div>

      <div style={{display:"flex",justifyContent:"center",gap:6,marginBottom:10}}>
        {["−15","+15","+30"].map(x => (
          <div key={x} onClick={()=>setT(Math.max(0, t + parseInt(x)))} style={{cursor:"pointer",padding:"6px 14px",borderRadius:999,border:"1.5px solid var(--ink-faint)",fontFamily:'Geist Mono, monospace',fontSize:11,letterSpacing:".08em",color:"var(--ink)",fontWeight:600}}>{x}s</div>
        ))}
      </div>

      {nextEx && nextSet && (
        <div className="card" style={{padding:"12px 14px",borderColor:"var(--accent)",borderWidth:2,display:"flex",alignItems:"center",gap:12}}>
          <div style={{width:36,height:36,borderRadius:"50%",background:"var(--accent)",color:"var(--on-accent)",display:"flex",alignItems:"center",justifyContent:"center",fontFamily:'Oswald, sans-serif',fontWeight:700,fontSize:16,border:"2px solid var(--ink)",flex:"none"}}>{nextSetIdx+1}</div>
          <div style={{flex:1,minWidth:0}}>
            <Eyebrow style={{fontSize:9}}>UP NEXT{nextEx.ss?` · ${nextEx.ssLabel}`:""}</Eyebrow>
            <div style={{fontFamily:'Hanken Grotesk, sans-serif',fontWeight:700,fontSize:14,color:"var(--ink)",overflow:"hidden",textOverflow:"ellipsis",whiteSpace:"nowrap"}}>{nextEx.name}{nextSet.wt?` · ${nextSet.wt}lb`:""}</div>
          </div>
          <div style={{fontFamily:'Oswald, sans-serif',fontWeight:700,fontSize:28,color:"var(--accent)",letterSpacing:"-.01em"}}>{nextSet.reps ?? "∞"}</div>
        </div>
      )}

      <div style={{padding:"10px 0 18px"}}>
        <Btn size="lg" onClick={onDone} style={{width:"100%"}}>Skip rest {I.fwd}</Btn>
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// SUMMARY
// ─────────────────────────────────────────────────────────────
function SummaryScreen({ onDone, go }){
  return (
    <div className="body">
      <TopBar eyebrow="WORKOUT COMPLETE · MAY 28" right={I.dots} />
      <h1 className="h1" style={{fontSize:32}}>Chest & Tris.</h1>
      <div className="sub">Day 23 · push / pull / legs</div>

      <div style={{display:"grid",gridTemplateColumns:"1fr 1fr",gap:8,marginTop:14}}>
        <StatBox label="VOLUME" value="12.4" unit="K" sub="lbs total" />
        <StatBox label="TIME" value="58" unit="M" sub="elapsed" />
        <StatBox label="SETS" value="18" unit="/18" sub="complete" dim />
        <StatBox label="PR" value="+1" sub="Flat machine" accent />
      </div>

      <Eyebrow style={{marginTop:12,marginBottom:6}}>LOG</Eyebrow>
      <div className="scroll" style={{gap:6}}>
        {[
          ["Flat Machine Press","15·12·10·8 @ 140lb","5.7k",true],
          ["Incline DB Press","15·12·10·8 @ 60lb","2.7k"],
          ["Close Grip DB","12·10·8 @ 55lb","1.7k"],
          ["Tri / Lat superset","3 rounds","1.4k"],
          ["Shoulder Press","12·10·8·6 @ 90lb","800"],
          ["Plate Tri Ext","3×12 @ 70lb","2.5k"],
          ["Tricep Pushup","To failure · 18","BW"],
        ].map(([n,sub,vol,pr],i) => (
          <div key={i} className="row" style={{padding:"9px 12px"}}>
            <div className="badge" style={{width:20,height:20,fontSize:10}}>{i+1}</div>
            <div className="nm"><div className="nm-name" style={{fontSize:13}}>{n}</div><div className="nm-sub" style={{fontSize:9}}>{sub}</div></div>
            {pr && <PrTag/>}
            <span className="end" style={{fontSize:15,marginLeft:6}}>{vol}</span>
          </div>
        ))}
      </div>

      <div style={{display:"flex",gap:8,padding:"10px 0 18px"}}>
        <Btn kind="secondary" size="sm">Edit log</Btn>
        <Btn size="lg" onClick={onDone} style={{flex:1}}>Done {I.fwd}</Btn>
      </div>
    </div>
  );
}

function StatBox({label, value, unit, sub, accent, dim}){
  return (
    <div className="card flat" style={{padding:"12px 14px",borderColor:accent?"var(--accent)":"var(--ink-faint)",borderStyle:accent?"solid":"dashed"}}>
      <Eyebrow style={{fontSize:9,color:accent?"var(--accent-2)":"var(--ink-soft)"}}>{label}</Eyebrow>
      <div style={{fontFamily:'Oswald, sans-serif',fontWeight:700,fontSize:36,color:accent?"var(--accent)":"var(--ink)",letterSpacing:"-.02em",lineHeight:.85,marginTop:2}}>{value}{unit&&<span style={{fontFamily:'Hanken Grotesk, sans-serif',fontSize:14,marginLeft:2,fontWeight:800,opacity:dim?.5:1,color:accent?"var(--accent)":"var(--accent-2)"}}>{unit}</span>}</div>
      <Eyebrow style={{fontSize:9,marginTop:2}}>{sub}</Eyebrow>
    </div>
  );
}
function PrTag(){
  return <div style={{padding:"2px 6px",borderRadius:6,background:"var(--accent-2)",color:"var(--on-accent)",fontFamily:'Geist Mono, monospace',fontSize:9,letterSpacing:".1em",fontWeight:600}}>PR</div>;
}

// ─────────────────────────────────────────────────────────────
// LIBRARY
// ─────────────────────────────────────────────────────────────

// Catalog of exercises, grouped by muscle. `top` seeds the history synth.
const EXERCISE_CATALOG = [
  { group:"Chest", items:[
    {id:"flat", name:"Flat Machine Chest Press", equip:"MACHINE", top:150, variations:["D-bar","Neutral","Wide"]},
    {id:"incline", name:"Incline DB Press", equip:"DUMBBELL", top:70, variations:[]},
    {id:"closegrip", name:"Close Grip DB Press", equip:"DUMBBELL", top:65, variations:[]},
    {id:"cablefly", name:"Cable Fly", equip:"CABLE", top:40, variations:["High","Low"]},
    {id:"bench", name:"Barbell Bench Press", equip:"BARBELL", top:275, variations:[], pr:true},
  ]},
  { group:"Back", items:[
    {id:"pulldown", name:"Lat Pulldown", equip:"CABLE", top:175, variations:["D-bar","Neutral Grip","Wide"], pr:true},
    {id:"row", name:"Seated Cable Row", equip:"CABLE", top:160, variations:[]},
    {id:"deadlift", name:"Deadlift", equip:"BARBELL", top:415, variations:[], pr:true},
  ]},
  { group:"Legs", items:[
    {id:"squat", name:"Back Squat", equip:"BARBELL", top:365, variations:[], pr:true},
    {id:"legpress", name:"Leg Press", equip:"MACHINE", top:450, variations:[]},
    {id:"legext", name:"Leg Extension", equip:"MACHINE", top:160, variations:[]},
  ]},
  { group:"Shoulders", items:[
    {id:"ohp", name:"Overhead Press", equip:"BARBELL", top:165, variations:[], pr:true},
    {id:"shoulder", name:"Shoulder Press Machine", equip:"MACHINE", top:100, variations:[]},
    {id:"latraise", name:"Lateral Raise", equip:"CABLE", top:20, variations:["Cable","DB"]},
  ]},
  { group:"Triceps", items:[
    {id:"tricable", name:"Tricep Cable Ext.", equip:"CABLE", top:50, variations:["Rope","Bar"]},
    {id:"platetri", name:"Plate Tricep Extension", equip:"MACHINE", top:70, variations:[]},
    {id:"pushup", name:"Tricep Push Up", equip:"BODYWEIGHT", top:0, variations:[]},
  ]},
];
const CATALOG_BY_ID = {};
EXERCISE_CATALOG.forEach(g => g.items.forEach(it => CATALOG_BY_ID[it.id] = {...it, group:g.group}));

function ExerciseDetailScreen({ exId, onBack }){
  const ex = CATALOG_BY_ID[exId] || EXERCISE_CATALOG[0].items[0];
  const variations = ["All", ...(ex.variations||[])];
  const [vIdx, setVIdx] = useState(ex.variations && ex.variations.length ? 1 : 0);
  const hist = synthHistory(ex.top, "12·10·8");
  const maxVol = Math.max(...hist.map(h=>parseFloat(h.vol)||0), 1);

  return (
    <div className="body">
      <TopBar onBack={onBack} eyebrow={`${ex.group.toUpperCase()} · ${ex.equip}`} right={I.dots} />
      <h1 className="h1" style={{fontSize:28,lineHeight:.98}}>{ex.name}.</h1>

      {variations.length > 1 && (
        <div style={{display:"flex",gap:6,overflowX:"auto",marginTop:10,paddingBottom:2}}>
          {variations.map((v,i)=>(
            <div key={i} onClick={()=>setVIdx(i)} style={{cursor:"pointer",padding:"6px 12px",borderRadius:999,whiteSpace:"nowrap",flexShrink:0,border:"1.5px solid "+(vIdx===i?"var(--accent)":"var(--ink-faint)"),background:vIdx===i?"var(--accent)":"transparent",color:vIdx===i?"var(--on-accent)":"var(--ink-soft)",fontFamily:'Geist Mono, monospace',fontSize:10,fontWeight:600,letterSpacing:".1em",textTransform:"uppercase"}}>{v}</div>
          ))}
        </div>
      )}

      <div className="scroll" style={{marginTop:12,gap:8}}>
        {ex.top > 0 && (
          <div className="card accent" style={{padding:"14px 16px 16px"}}>
            <Eyebrow style={{opacity:.85}}>PERSONAL BEST{ex.pr?" · TRACKED":""}</Eyebrow>
            <Lockup num={ex.top} top={hist[0].d.split(" · ")[0]} topColor="var(--on-accent)" bot={<span>lbs ·<br/>top set.</span>} size={72} />
          </div>
        )}

        <Eyebrow style={{marginTop:2,marginBottom:2}}>VOLUME · LAST 4</Eyebrow>
        <div style={{display:"flex",alignItems:"flex-end",gap:6,height:56}}>
          {[...hist].reverse().map((h,i)=>{
            const v = parseFloat(h.vol)||0;
            const last = i===hist.length-1;
            return <div key={i} style={{flex:1,height:`${Math.max(8,v/maxVol*48)}px`,background:last?"var(--accent-2)":"var(--accent)",opacity:last?1:.55,borderRadius:"3px 3px 0 0"}}></div>;
          })}
        </div>

        <Eyebrow style={{marginTop:8,marginBottom:2}}>LAST 4 SESSIONS</Eyebrow>
        {hist.map((h,i)=>(
          <div key={i} className="row" style={{borderColor:i===0?"var(--accent)":"var(--ink-faint)",borderWidth:i===0?2:1.5}}>
            <div className="nm"><div className="nm-name" style={{fontSize:13}}>{h.d}</div><div className="nm-sub">{h.line} REPS</div></div>
            <div style={{textAlign:"right"}}>
              <div style={{fontFamily:'Oswald, sans-serif',fontWeight:700,fontSize:18,color:i===0?"var(--accent)":"var(--ink)",letterSpacing:"-.01em",lineHeight:.9}}>{h.top}</div>
              <div className="nm-sub">{h.vol} VOL</div>
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}

function LibraryScreen({ go }){
  const [filter, setFilter] = useState("All");
  const [creating, setCreating] = useState(false);
  const filters = ["All","Workouts","Folders","Exercises","Programs"];
  return (
    <div className="body">
      <TopBar eyebrow="LIBRARY" right={I.plus} onRight={()=>setCreating(true)} />
      {creating && <CreateSheet onClose={()=>setCreating(false)} onPick={(k)=>{ setCreating(false); go(k==="workout"?"builder":k); }} />}
      <h1 className="h1">Library.</h1>
      <div style={{display:"flex",alignItems:"center",gap:8,marginTop:10,padding:"10px 14px",borderRadius:14,background:"var(--surface)",border:"1.5px solid var(--ink-faint)"}}>
        <span style={{fontFamily:'Hanken Grotesk, sans-serif',fontWeight:500,fontSize:13,color:"var(--ink-soft)"}}>Search workouts, exercises…</span>
      </div>
      <div style={{display:"flex",gap:6,marginTop:12,overflowX:"auto"}}>
        {filters.map((l,i)=>(
          <FilterChip key={i} on={filter===l} onClick={()=>setFilter(l)}>{l}</FilterChip>
        ))}
      </div>

      {filter==="Exercises" ? (
        <div className="scroll" style={{marginTop:14,gap:8}}>
          {EXERCISE_CATALOG.map((grp,gi)=>(
            <div key={gi}>
              <Eyebrow style={{marginBottom:6,marginTop:gi===0?0:8}}>{grp.group.toUpperCase()} · {grp.items.length}</Eyebrow>
              <div style={{display:"flex",flexDirection:"column",gap:6}}>
                {grp.items.map((it,ii)=>(
                  <div key={ii} className="row" style={{cursor:"pointer"}} onClick={()=>go("exdetail:"+it.id)}>
                    <div className="nm"><div className="nm-name">{it.name}</div><div className="nm-sub">{it.equip}{it.variations.length?` · ${it.variations.length} variations`:""}</div></div>
                    {it.pr && <PrTag/>}
                    <span style={{marginLeft:6}}>{I.chev}</span>
                  </div>
                ))}
              </div>
            </div>
          ))}
        </div>
      ) : (
        <div className="scroll" style={{marginTop:14,gap:8}}>
          <Eyebrow style={{marginBottom:-2}}>FOLDERS · 3</Eyebrow>
          {LIBRARY_FOLDERS.map((f,i) => (
            <div key={i} className="row" style={{padding:"14px 14px",cursor:"pointer"}} onClick={()=>f.program && go("program")}>
              <FolderIcon color={f.color} />
              <div className="nm"><div className="nm-name">{f.name}</div><div className="nm-sub">{f.sub}</div></div>
              <span>{I.chev}</span>
            </div>
          ))}
          <div style={{display:"flex",justifyContent:"space-between",alignItems:"baseline",marginTop:6}}>
            <Eyebrow>RECENT</Eyebrow>
            <Eyebrow style={{cursor:"pointer"}} onClick={()=>setFilter("Exercises")}>BROWSE EXERCISES →</Eyebrow>
          </div>
          {[["Chest & Tris","7 exercises · used today"],["Back & Bis","6 exercises · 5d ago"],["Leg day","5 exercises · 7d ago"]].map(([n,s],i)=>(
            <div key={i} className="row"><div className="nm"><div className="nm-name">{n}</div><div className="nm-sub">{s}</div></div><span>{I.chev}</span></div>
          ))}
        </div>
      )}
    </div>
  );
}

function FolderIcon({color}){
  return (
    <div style={{width:30,height:30,borderRadius:7,background:color,border:"1.5px solid var(--ink)",position:"relative",flex:"none"}}>
      <div style={{position:"absolute",top:-3,left:6,width:14,height:5,background:color,borderTop:"1.5px solid var(--ink)",borderLeft:"1.5px solid var(--ink)",borderRight:"1.5px solid var(--ink)",borderRadius:"3px 3px 0 0"}}></div>
    </div>
  );
}
function FilterChip({children, on, onClick, accent}){
  return <div onClick={onClick} style={{cursor:onClick?"pointer":"default",padding:"5px 12px",borderRadius:999,border:`1.5px solid ${on?(accent?"var(--accent)":"var(--ink)"):"var(--ink-faint)"}`,background:on?(accent?"var(--accent)":"var(--ink)"):"transparent",color:on?(accent?"var(--on-accent)":"var(--bg)"):"var(--ink-soft)",fontFamily:'Geist Mono, monospace',fontSize:10,fontWeight:600,letterSpacing:".12em",textTransform:"uppercase",whiteSpace:"nowrap",flexShrink:0}}>{children}</div>;
}

// ─────────────────────────────────────────────────────────────
// PROGRAM DETAIL
// ─────────────────────────────────────────────────────────────
function ProgramScreen({ onBack, go, onStartWorkout }){
  const [week, setWeek] = useState(4);
  return (
    <div className="body">
      <TopBar onBack={onBack} eyebrow="PROGRAM · ACTIVE" right={I.dots} />
      <h1 className="h1" style={{fontSize:28}}>Push / Pull / Legs.</h1>
      <div className="sub">12 weeks · 5 days/wk · intermediate</div>

      <div style={{display:"flex",gap:6,overflowX:"auto",marginTop:12,paddingBottom:4}}>
        {Array.from({length:8}).map((_,i)=>(
          <div key={i} onClick={()=>setWeek(i+1)} style={{cursor:"pointer",padding:"6px 12px",borderRadius:999,border:"1.5px solid "+(week===i+1?"var(--accent)":"var(--ink-faint)"),background:week===i+1?"var(--accent)":"transparent",color:week===i+1?"var(--on-accent)":"var(--ink)",fontFamily:'Geist Mono, monospace',fontSize:10,fontWeight:600,letterSpacing:".12em",textTransform:"uppercase",whiteSpace:"nowrap",flexShrink:0}}>WK {i+1}</div>
        ))}
      </div>

      <div className="card accent" style={{marginTop:12}}>
        <Eyebrow style={{opacity:.85}}>WEEK {week} · PROGRESS</Eyebrow>
        <Lockup num={<span>3<span style={{fontFamily:'Hanken Grotesk, sans-serif',fontSize:20,opacity:.6,marginLeft:4}}>/5</span></span>} top="Done" bot={<span>Two<br/>to go.</span>} size={60} />
      </div>

      <Eyebrow style={{marginTop:14,marginBottom:8}}>THIS WEEK</Eyebrow>
      <div className="scroll" style={{gap:8}}>
        {WEEK.filter(w=>w.state!=="rest").map((w,i) => {
          const isToday = w.state==="today";
          return (
            <div key={i} className="row" onClick={()=>isToday && onStartWorkout()} style={{cursor:isToday?"pointer":"default",borderColor:isToday?"var(--accent)":"var(--ink-faint)",borderWidth:isToday?2:1.5,opacity:w.state==="done"?.55:1}}>
              <div className="badge" style={w.state==="done"?{background:"var(--ink)",color:"var(--bg)",borderColor:"var(--ink)"}:isToday?{background:"var(--accent)",color:"var(--on-accent)",borderColor:"var(--accent)"}:{}}>{w.d}</div>
              <div className="nm"><div className="nm-name">{w.label}</div><div className="nm-sub">{w.state==="done"?`DONE · ${w.time} · ${w.vol} LBS`:isToday?"TODAY · ~55M":"UPCOMING · ~45M"}</div></div>
              <span className="end" style={{color:isToday?"var(--accent)":"var(--ink)"}}>{w.state==="done"?"✓":isToday?"→":I.chev}</span>
            </div>
          );
        })}
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// PLAN (agenda)
// ─────────────────────────────────────────────────────────────
function PlanScreen({ go, onStartWorkout }){
  const [view, setView] = useState("calendar"); // calendar | agenda
  // scheduled workouts by day-of-month (editable). seed past + upcoming.
  const [sched, setSched] = useState(()=>{
    const m={};
    [1,2,4,5,6,8,9,11,12,13,15,16,18,19,20,22,23,25,26,27].forEach(d=>m[d]={state:"done"});
    m[28]={state:"today", nm:"Chest & Tris"};
    m[29]={state:"plan", nm:"Shoulders"};
    m[30]={state:"plan", nm:"Arms · finisher"};
    return m;
  });
  const [schedDay, setSchedDay] = useState(null); // day being scheduled

  const agenda = [
    {d:"28",dy:"WED",nm:"Chest & Tris",sub:"7 exercises · ~60m",today:true},
    {d:"29",dy:"THU",nm:"Shoulders",sub:"5 exercises · ~55m"},
    {d:"30",dy:"FRI",nm:"Arms · finisher",sub:"4 exercises · ~45m"},
    {d:"31",dy:"SAT",nm:"Rest",sub:""},
    {d:"01",dy:"SUN",nm:"Rest",sub:""},
    {d:"02",dy:"MON",nm:"Chest & Tris",sub:"7 exercises · ~60m"},
    {d:"03",dy:"TUE",nm:"Back & Bis",sub:"6 exercises · ~62m"},
  ];
  const monthStart = 4; // May 1 2026 = Friday
  const cells = [];
  for(let i=0;i<monthStart;i++) cells.push(null);
  for(let d=1;d<=31;d++) cells.push(d);

  function assign(day, nm){ setSched(s=>({...s,[day]:{state:day===28?"today":"plan", nm}})); setSchedDay(null); }
  function clearDay(day){ setSched(s=>{ const c={...s}; delete c[day]; return c; }); setSchedDay(null); }

  return (
    <div className="body">
      <TopBar eyebrow="PLAN" right={view==="calendar"?I.cal:I.plus} onRight={()=>setView(v=>v==="calendar"?"agenda":"calendar")} />

      {/* segmented toggle */}
      <div style={{display:"flex",gap:4,padding:4,background:"var(--surface)",borderRadius:999,border:"1.5px solid var(--ink-faint)",marginBottom:12}}>
        {[["calendar","Calendar"],["agenda","Agenda"]].map(([k,l])=>(
          <button key={k} type="button" onClick={()=>setView(k)} style={{flex:1,appearance:"none",cursor:"pointer",border:0,borderRadius:999,padding:"8px 0",background:view===k?"var(--ink)":"transparent",color:view===k?"var(--bg)":"var(--ink-soft)",fontFamily:'Geist Mono, monospace',fontSize:11,fontWeight:600,letterSpacing:".1em",textTransform:"uppercase"}}>{l}</button>
        ))}
      </div>

      {view==="calendar" ? (
        <div className="scroll" style={{gap:0}}>
          <div style={{display:"flex",alignItems:"baseline",justifyContent:"space-between",marginBottom:10}}>
            <h1 className="h1" style={{fontSize:32}}>May.</h1>
            <span style={{fontFamily:'Oswald, sans-serif',fontWeight:700,fontSize:24,color:"var(--ink-soft)",letterSpacing:"-.01em"}}>2026</span>
          </div>

          <div className="card accent" style={{padding:"10px 14px",marginBottom:14}}>
            <div style={{display:"flex",justifyContent:"space-between",alignItems:"center"}}>
              <div>
                <Eyebrow style={{opacity:.85,fontSize:9}}>THIS MONTH</Eyebrow>
                <div style={{fontFamily:'Oswald, sans-serif',fontWeight:700,fontSize:30,letterSpacing:"-.01em",lineHeight:.85,marginTop:2}}>20<span style={{fontFamily:'Hanken Grotesk, sans-serif',fontSize:13,marginLeft:4,fontWeight:700,opacity:.6}}>/ 22</span></div>
              </div>
              <div style={{fontFamily:'Oswald, sans-serif',fontWeight:700,fontSize:26,color:"var(--on-accent)",letterSpacing:"-.01em"}}>91%</div>
            </div>
          </div>

          {/* weekday header */}
          <div style={{display:"grid",gridTemplateColumns:"repeat(7,1fr)",gap:4,marginBottom:6}}>
            {["M","T","W","T","F","S","S"].map((d,i)=>(
              <div key={i} style={{textAlign:"center",fontFamily:'Geist Mono, monospace',fontSize:9,letterSpacing:".1em",color:"var(--ink-soft)",fontWeight:500}}>{d}</div>
            ))}
          </div>
          {/* day grid */}
          <div style={{display:"grid",gridTemplateColumns:"repeat(7,1fr)",gap:4}}>
            {cells.map((d,i)=>{
              if(d===null) return <div key={i}></div>;
              const entry = sched[d];
              const st = entry?entry.state:"";
              const isToday = st==="today";
              return (
                <div key={i} onClick={()=>{ if(isToday) onStartWorkout(); else setSchedDay(d); }} style={{
                  aspectRatio:1,display:"flex",flexDirection:"column",alignItems:"center",justifyContent:"center",
                  borderRadius:8,cursor:"pointer",
                  fontFamily:'Hanken Grotesk, sans-serif',fontSize:12,fontWeight:700,
                  background:st==="done"?"var(--accent)":st==="plan"?"var(--ink-faint)":"transparent",
                  color:st==="done"?"var(--on-accent)":"var(--ink)",
                  border:isToday?"2px solid var(--accent-2)":st===""?"1px dashed var(--ink-faint)":"0",
                }}>
                  {d}
                  {st==="done" && <div style={{width:4,height:4,borderRadius:"50%",background:"var(--on-accent)",marginTop:1}}></div>}
                  {(st==="today"||st==="plan") && <div style={{width:4,height:4,borderRadius:"50%",background:"var(--accent-2)",marginTop:1}}></div>}
                </div>
              );
            })}
          </div>

          <Eyebrow style={{marginTop:14,marginBottom:6}}>WED · MAY 28</Eyebrow>
          <div className="row" onClick={onStartWorkout} style={{cursor:"pointer",borderColor:"var(--accent)",borderWidth:2}}>
            <div className="badge" style={{background:"var(--accent)",color:"var(--on-accent)",borderColor:"var(--accent)"}}>T</div>
            <div className="nm"><div className="nm-name">Chest & Tris</div><div className="nm-sub">7 EXERCISES · ~60M</div></div>
            <span className="end" style={{color:"var(--accent)"}}>→</span>
          </div>
        </div>
      ) : (
        <div className="scroll" style={{gap:6}}>
          {agenda.map((a,i) => (
            <div key={i} style={{display:"flex",gap:12,alignItems:"center"}}>
              <div style={{textAlign:"center",minWidth:46}}>
                <Eyebrow style={{fontSize:9,color:a.today?"var(--accent-2)":"var(--ink-soft)"}}>{a.dy}</Eyebrow>
                <div style={{fontFamily:'Oswald, sans-serif',fontWeight:700,fontSize:a.today?40:30,color:a.today?"var(--accent)":a.sub?"var(--ink)":"var(--ink-soft)",letterSpacing:"-.02em",lineHeight:.85}}>{a.d}</div>
              </div>
              <div className="row" onClick={()=>a.today && onStartWorkout()} style={{flex:1,cursor:a.today?"pointer":"default",opacity:!a.sub?.5:1,borderColor:a.today?"var(--accent)":"var(--ink-faint)",borderWidth:a.today?2:1.5}}>
                <div className="nm"><div className="nm-name">{a.nm}</div>{a.sub&&<div className="nm-sub">{a.sub}</div>}</div>
                {a.sub && <span className="end" style={{color:a.today?"var(--accent)":"var(--ink)"}}>{a.today?"→":I.chev}</span>}
              </div>
            </div>
          ))}
        </div>
      )}

      {schedDay!=null && <ScheduleSheet day={schedDay} entry={sched[schedDay]} onClose={()=>setSchedDay(null)} onAssign={assign} onClear={clearDay} />}
    </div>
  );
}

function ScheduleSheet({ day, entry, onClose, onAssign, onClear }){
  const done = entry && entry.state==="done";
  return (
    <Sheet eyebrow={`MAY ${day} · 2026`} title={entry?(done?"Completed.":"Scheduled."):"Schedule a day."} onClose={onClose}>
      {entry && (
        <div className="row" style={{flexShrink:0,marginBottom:10,borderColor:done?"var(--accent)":"var(--accent-2)",borderWidth:2}}>
          <div className="nm"><div className="nm-name">{entry.nm||"Workout"}</div><div className="nm-sub">{done?"DONE":"PLANNED"}</div></div>
          {!done && <button type="button" onClick={()=>onClear(day)} style={{appearance:"none",border:0,background:"transparent",cursor:"pointer",color:"var(--ink-soft)",fontFamily:'Geist Mono, monospace',fontSize:9,letterSpacing:".1em",textTransform:"uppercase",fontWeight:600}}>CLEAR</button>}
        </div>
      )}
      {!done && (
        <div style={{display:"contents"}}>
          <Eyebrow style={{flexShrink:0,marginBottom:6}}>{entry?"REPLACE WITH":"PICK A WORKOUT"}</Eyebrow>
          <div className="sheet-scroll" style={{gap:6}}>
            {SAVED_WORKOUTS.map((w,i)=>(
              <div key={i} className="row" onClick={()=>onAssign(day,w.nm)} style={{cursor:"pointer"}}>
                <div className="nm"><div className="nm-name">{w.nm}</div><div className="nm-sub">{w.sub}</div></div>
                <div className="icon-btn" style={{width:28,height:28,fontSize:14,borderColor:"var(--accent)",color:"var(--accent)"}}>+</div>
              </div>
            ))}
            <div className="row" onClick={()=>onAssign(day,"Rest")} style={{cursor:"pointer",borderStyle:"dashed"}}>
              <div className="nm"><div className="nm-name">Rest day</div><div className="nm-sub">RECOVERY</div></div>
            </div>
          </div>
        </div>
      )}
    </Sheet>
  );
}

// ─────────────────────────────────────────────────────────────
// YOU / STATS / PRS / HISTORY / SESSION DETAIL
// ─────────────────────────────────────────────────────────────
function YouScreen({ go, palette, setPalette }){
  return (
    <div className="body">
      <TopBar eyebrow="YOU" right={I.dots} />
      <div style={{display:"flex",alignItems:"center",gap:14,marginTop:2}}>
        <div style={{width:56,height:56,borderRadius:"50%",background:"var(--accent)",color:"var(--on-accent)",display:"flex",alignItems:"center",justifyContent:"center",fontFamily:'Oswald, sans-serif',fontWeight:700,fontSize:30,border:"2px solid var(--ink)"}}>A</div>
        <div><h1 className="h1" style={{fontSize:26}}>Alex Mason.</h1><div className="sub">Member since Feb 2024 · PPL</div></div>
      </div>

      <div style={{display:"grid",gridTemplateColumns:"1fr 1fr 1fr",gap:6,marginTop:14}}>
        <MiniStat label="STREAK" value="27" unit="d" accent2 />
        <MiniStat label="SESSIONS" value="183" />
        <MiniStat label="VOLUME" value="2.1" unit="M" accent />
      </div>

      <div className="scroll" style={{marginTop:14,gap:6}}>
        <Eyebrow style={{marginBottom:0}}>YOUR DATA</Eyebrow>
        <NavRow icon={<span style={{color:"var(--on-accent)"}}>{I.chart}</span>} iconBg="var(--accent)" name="Stats" sub="Volume, PRs, charts" onClick={()=>go("stats")} />
        <NavRow iconText="PR" iconBg="var(--accent-2)" name="Personal records" sub="8 lifts tracked" onClick={()=>go("prs")} />
        <NavRow iconText="H" iconBg="var(--ink-faint)" iconColor="var(--ink)" name="Workout history" sub="183 sessions logged" onClick={()=>go("history")} />

        <Eyebrow style={{marginTop:10,marginBottom:0}}>PALETTE</Eyebrow>
        <div className="row" style={{justifyContent:"space-between"}}>
          <div className="nm"><div className="nm-name">Theme</div><div className="nm-sub">{PALETTES[palette].label}</div></div>
          <div style={{display:"flex",gap:8}}>
            {Object.keys(PALETTES).map(k => (
              <div key={k} onClick={()=>setPalette(k)} style={{cursor:"pointer",width:26,height:26,borderRadius:"50%",background:PALETTES[k].accent,border:palette===k?"2px solid var(--ink)":"1.5px solid var(--ink-faint)",boxShadow:palette===k?"0 0 0 2px var(--accent-2)":"none"}}></div>
            ))}
          </div>
        </div>

        <Eyebrow style={{marginTop:10,marginBottom:0}}>PREFERENCES</Eyebrow>
        <div style={{borderRadius:14,overflow:"hidden",border:"1.5px solid var(--ink-faint)"}}>
          <SetRow label="Units" val="LBS · IMPERIAL" />
          <SetRow label="Default rest timer" val="90s" />
          <SetRow label="Auto-progress weight" toggle />
          <SetRow label="Sound on rest end" toggle />
        </div>
      </div>
    </div>
  );
}

function MiniStat({label, value, unit, accent, accent2}){
  return (
    <div className="card flat" style={{padding:"10px 10px"}}>
      <Eyebrow style={{fontSize:9,color:accent?"var(--accent)":accent2?"var(--accent-2)":"var(--ink-soft)"}}>{label}</Eyebrow>
      <div style={{fontFamily:'Oswald, sans-serif',fontWeight:700,fontSize:24,color:accent2?"var(--accent-2)":"var(--ink)",letterSpacing:"-.02em",lineHeight:.85,marginTop:2}}>{value}{unit&&<span style={{fontFamily:'Hanken Grotesk, sans-serif',fontSize:11,marginLeft:2,opacity:.7,fontWeight:700,color:"var(--ink)"}}>{unit}</span>}</div>
    </div>
  );
}
function NavRow({icon, iconText, iconBg, iconColor, name, sub, onClick}){
  return (
    <div className="row" onClick={onClick} style={{cursor:"pointer",padding:"12px 14px"}}>
      <div style={{width:32,height:32,borderRadius:8,background:iconBg,color:iconColor||"var(--on-accent)",display:"flex",alignItems:"center",justifyContent:"center",flex:"none",fontFamily:'Oswald, sans-serif',fontWeight:700,fontSize:14}}>{icon||iconText}</div>
      <div className="nm"><div className="nm-name">{name}</div><div className="nm-sub">{sub}</div></div>
      <span>{I.chev}</span>
    </div>
  );
}
function SetRow({label, val, toggle}){
  const [on, setOn] = useState(true);
  return (
    <div className="set-row">
      <div className="set-label">{label}</div>
      {toggle ? <div className={"switch"+(on?" on":"")} onClick={()=>setOn(!on)}></div> : <span className="set-val">{val}</span>}
      {!toggle && <span style={{opacity:.4,marginLeft:8}}>{I.chev}</span>}
    </div>
  );
}

function StatsScreen({ onBack }){
  return (
    <div className="body">
      <TopBar onBack={onBack} eyebrow="STATS" right={I.dots} />
      <h1 className="h1" style={{fontSize:30}}>Your numbers.</h1>
      <div style={{display:"flex",gap:6,marginTop:10,overflowX:"auto"}}>
        {[["7D",false],["30D",true],["3M",false],["YR",false],["ALL",false]].map(([l,on],i)=><FilterChip key={i} on={on}>{l}</FilterChip>)}
      </div>
      <div className="scroll" style={{marginTop:12,gap:8}}>
        <div className="card accent" style={{padding:"14px 16px 16px"}}>
          <Eyebrow style={{opacity:.85}}>30D VOLUME · LBS</Eyebrow>
          <Lockup num={<span>184<span style={{fontFamily:'Hanken Grotesk, sans-serif',fontSize:24,opacity:.85,marginLeft:2,fontWeight:800}}>K</span></span>} top="+12% vs prev" bot={<span>Trending<br/>up.</span>} size={80} />
          <div className="chart-bars" style={{height:50,marginTop:10}}>
            {[40,55,52,68,72,80,60,75,72,85,90,82].map((h,i)=><div key={i} style={{height:`${h}%`,background:"var(--on-accent)",opacity:.85,borderRadius:"3px 3px 0 0",flex:1}}></div>)}
          </div>
        </div>
        <div style={{display:"grid",gridTemplateColumns:"1fr 1fr",gap:6}}>
          <SmallStat label="SESSIONS" value="21" unit="/22" sub="OF PLAN" />
          <SmallStat label="NEW PRS" value="4" sub="THIS MONTH" accent />
          <SmallStat label="AVG TIME" value="62" unit="m" sub="PER SESSION" />
          <SmallStat label="STREAK" value="27" unit="d" sub="PERSONAL BEST" accent2 />
        </div>
        <Eyebrow style={{marginTop:10,marginBottom:2}}>VOLUME BY MUSCLE</Eyebrow>
        {[["Chest","42k",.95],["Back","38k",.85],["Legs","56k",1],["Shoulders","22k",.5],["Arms","18k",.4]].map(([n,v,pct],i)=>(
          <div key={i} style={{display:"flex",alignItems:"center",gap:10,marginBottom:4}}>
            <div style={{width:64,fontFamily:'Hanken Grotesk, sans-serif',fontWeight:600,fontSize:13,color:"var(--ink)"}}>{n}</div>
            <div style={{flex:1,height:18,background:"var(--ink-faint)",borderRadius:4,overflow:"hidden"}}><div style={{height:"100%",width:`${pct*100}%`,background:n==="Legs"?"var(--accent-2)":"var(--accent)"}}></div></div>
            <div style={{width:48,textAlign:"right",fontFamily:'Oswald, sans-serif',fontWeight:700,fontSize:16,color:"var(--ink)",letterSpacing:"-.01em"}}>{v}</div>
          </div>
        ))}
      </div>
    </div>
  );
}
function SmallStat({label, value, unit, sub, accent, accent2}){
  return (
    <div className="card" style={{padding:"12px 14px"}}>
      <Eyebrow style={{fontSize:9,color:accent?"var(--accent-2)":accent2?"var(--accent-2)":"var(--ink-soft)"}}>{label}</Eyebrow>
      <div style={{fontFamily:'Oswald, sans-serif',fontWeight:700,fontSize:32,letterSpacing:"-.02em",lineHeight:.85,marginTop:2,color:accent?"var(--accent)":accent2?"var(--accent-2)":"var(--ink)"}}>{value}{unit&&<span style={{fontFamily:'Hanken Grotesk, sans-serif',fontSize:11,marginLeft:2,opacity:.6,fontWeight:800,color:"var(--ink)"}}>{unit}</span>}</div>
      <Eyebrow style={{fontSize:9,marginTop:2}}>{sub}</Eyebrow>
    </div>
  );
}

function PRScreen({ onBack }){
  const hero = PRS.find(p=>p.hero);
  const rest = PRS.filter(p=>!p.hero);
  return (
    <div className="body">
      <TopBar onBack={onBack} eyebrow="PERSONAL RECORDS" right={I.dots} />
      <h1 className="h1" style={{fontSize:30}}>PRs.</h1>
      <div className="sub">8 lifts tracked · 4 new this month</div>
      <div style={{display:"flex",gap:6,marginTop:10,overflowX:"auto"}}>
        {[["All",true],["Chest",false],["Back",false],["Legs",false],["Arms",false]].map(([l,on],i)=><FilterChip key={i} on={on} accent>{l}</FilterChip>)}
      </div>
      <div className="scroll" style={{marginTop:12,gap:8}}>
        <div className="card accent" style={{padding:"14px 16px 16px"}}>
          <div style={{display:"flex",justifyContent:"space-between",alignItems:"flex-start"}}>
            <div style={{padding:"2px 8px",borderRadius:999,background:"var(--on-accent)",color:"var(--accent)",fontFamily:'Geist Mono, monospace',fontSize:9,fontWeight:600,letterSpacing:".14em",textTransform:"uppercase"}}>NEW · {hero.d}</div>
            <Eyebrow style={{opacity:.85}}>{hero.m}</Eyebrow>
          </div>
          <div style={{fontFamily:'Hanken Grotesk, sans-serif',fontWeight:800,fontSize:18,marginTop:4,letterSpacing:"-.01em",color:"var(--on-accent)"}}>{hero.n}</div>
          <div style={{display:"flex",alignItems:"baseline",gap:14,marginTop:4}}>
            <span style={{fontFamily:'Oswald, sans-serif',fontWeight:700,fontSize:64,letterSpacing:"-.02em",lineHeight:.82,color:"var(--on-accent)"}}>{hero.w}<span style={{fontFamily:'Hanken Grotesk, sans-serif',fontSize:14,marginLeft:4,fontWeight:800,opacity:.85}}>lb</span></span>
            <span style={{fontFamily:'Oswald, sans-serif',fontWeight:700,fontSize:34,letterSpacing:"-.02em",color:"var(--accent-2)"}}>{hero.r}</span>
          </div>
        </div>
        <div style={{display:"grid",gridTemplateColumns:"1fr 1fr",gap:6}}>
          {rest.map((p,i)=>(
            <div key={i} className="card" style={{padding:"12px 14px",borderColor:p.fresh?"var(--accent-2)":"var(--ink-faint)",borderWidth:p.fresh?2:1.5}}>
              <div style={{display:"flex",justifyContent:"space-between",alignItems:"baseline"}}>
                <Eyebrow style={{fontSize:9}}>{p.m}</Eyebrow>
                {p.fresh && <Eyebrow style={{fontSize:9,color:"var(--accent-2)"}}>NEW</Eyebrow>}
              </div>
              <div style={{fontFamily:'Hanken Grotesk, sans-serif',fontWeight:700,fontSize:13,color:"var(--ink)",marginTop:2}}>{p.n}</div>
              <div style={{display:"flex",alignItems:"baseline",gap:6,marginTop:2}}>
                <span style={{fontFamily:'Oswald, sans-serif',fontWeight:700,fontSize:24,letterSpacing:"-.02em",color:"var(--ink)"}}>{p.w}<span style={{fontFamily:'Hanken Grotesk, sans-serif',fontSize:10,marginLeft:2,opacity:.6,fontWeight:800}}>lb</span></span>
                <span style={{fontFamily:'Oswald, sans-serif',fontWeight:700,fontSize:14,letterSpacing:"-.01em",color:"var(--accent-2)"}}>{p.r}</span>
              </div>
              <Eyebrow style={{fontSize:9,marginTop:2}}>{p.d}</Eyebrow>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}

function HistoryScreen({ onBack, go }){
  return (
    <div className="body">
      <TopBar onBack={onBack} eyebrow="WORKOUT HISTORY" right={I.dots} />
      <h1 className="h1" style={{fontSize:30}}>History.</h1>
      <div className="sub">183 sessions · since Feb 2024</div>
      <div style={{display:"flex",gap:6,marginTop:10,overflowX:"auto"}}>
        {[["All",true],["PPL",false],["One-offs",false],["+ PR",false]].map(([l,on],i)=><FilterChip key={i} on={on}>{l}</FilterChip>)}
      </div>
      <div className="scroll" style={{marginTop:12,gap:6}}>
        <Eyebrow style={{marginBottom:0}}>THIS WEEK</Eyebrow>
        {RECENT.slice(0,2).map((r,i)=>(
          <div key={i} className="row" onClick={()=>go("session-detail")} style={{cursor:"pointer",padding:"10px 12px"}}>
            <div style={{minWidth:46}}><Eyebrow style={{fontSize:9}}>{r.dy}</Eyebrow><div style={{fontFamily:'Oswald, sans-serif',fontWeight:700,fontSize:16,color:"var(--ink)",letterSpacing:"-.01em",lineHeight:.85}}>{r.d.replace("MAY ","")}</div></div>
            <div className="nm"><div className="nm-name">{r.name}</div><div className="nm-sub">{r.sub}</div></div>
            {r.pr && <PrTag/>}
            <span style={{marginLeft:6}}>{I.chev}</span>
          </div>
        ))}
        <Eyebrow style={{marginTop:8,marginBottom:0}}>LAST WEEK</Eyebrow>
        {RECENT.slice(2).map((r,i)=>(
          <div key={i} className="row" onClick={()=>go("session-detail")} style={{cursor:"pointer",padding:"10px 12px"}}>
            <div style={{minWidth:46}}><Eyebrow style={{fontSize:9}}>{r.dy}</Eyebrow><div style={{fontFamily:'Oswald, sans-serif',fontWeight:600,fontSize:14,color:"var(--ink-soft)",letterSpacing:"-.01em",lineHeight:.85}}>{r.d.replace("MAY ","")}</div></div>
            <div className="nm"><div className="nm-name">{r.name}</div><div className="nm-sub">{r.sub}</div></div>
            {r.pr && <PrTag/>}
            <span style={{marginLeft:6}}>{I.chev}</span>
          </div>
        ))}
      </div>
    </div>
  );
}

function SessionDetailScreen({ onBack }){
  return (
    <div className="body">
      <TopBar onBack={onBack} eyebrow="WED · MAY 21 · 58M" right={I.dots} />
      <h1 className="h1" style={{fontSize:30}}>Chest & Tris.</h1>
      <div className="sub">PPL · Week 3 · Day 18 · completed</div>
      <div style={{display:"grid",gridTemplateColumns:"1fr 1fr",gap:6,marginTop:12}}>
        <StatBox label="VOLUME" value="12.4" unit="K" sub="lbs" />
        <StatBox label="PR" value="+1" sub="Flat machine" accent />
      </div>
      <Eyebrow style={{marginTop:12,marginBottom:6}}>LOG</Eyebrow>
      <div className="scroll" style={{gap:6}}>
        {[
          ["Flat Machine Press","15·12·10·8 @ 140lb","5.7k",true],
          ["Incline DB Press","15·12·10·8 @ 60lb","2.7k"],
          ["Close Grip DB","12·10·8 @ 55lb","1.7k"],
          ["Tri / Lat superset","3 rounds","1.4k"],
          ["Shoulder Press","12·10·8·6 @ 90lb","800"],
          ["Plate Tri Ext","3×12 @ 70lb","2.5k"],
          ["Tricep Pushup","To failure · 18","BW"],
        ].map(([n,sub,vol,pr],i)=>(
          <div key={i} className="row" style={{padding:"10px 12px"}}>
            <div className="badge" style={{width:20,height:20,fontSize:10}}>{i+1}</div>
            <div className="nm"><div className="nm-name" style={{fontSize:13}}>{n}</div><div className="nm-sub" style={{fontSize:9}}>{sub}</div></div>
            {pr && <PrTag/>}
            <span className="end" style={{fontSize:14,marginLeft:6}}>{vol}</span>
          </div>
        ))}
      </div>
      <div style={{display:"flex",gap:8,padding:"10px 0 18px"}}>
        <Btn kind="secondary" size="sm">Duplicate</Btn>
        <Btn size="sm" style={{flex:1}}>Repeat workout {I.fwd}</Btn>
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// CREATE CHOOSER + WORKOUT BUILDER + ROUTINE + FOLDER
// ─────────────────────────────────────────────────────────────
function CreateSheet({ onClose, onPick }){
  const opts = [
    {k:"workout", name:"Workout", sub:"A single session you can run", icon:I.bolt, color:"var(--accent)"},
    {k:"routine", name:"Routine", sub:"A multi-week program of workouts", icon:I.cal, color:"var(--accent-2)"},
    {k:"folder", name:"Folder", sub:"Group workouts together", icon:"▣", color:"var(--ink-faint)"},
  ];
  return (
    <Sheet eyebrow="CREATE NEW" title="What are you making?" onClose={onClose}>
      <div className="sheet-scroll" style={{gap:8,paddingBottom:8}}>
        {opts.map(o=>(
          <div key={o.k} className="row" onClick={()=>onPick(o.k)} style={{cursor:"pointer",padding:"14px 14px"}}>
            <div style={{width:38,height:38,borderRadius:10,flex:"none",display:"flex",alignItems:"center",justifyContent:"center",background:o.color,color:o.k==="folder"?"var(--ink)":"var(--on-accent)",fontFamily:'Hanken Grotesk, sans-serif',fontWeight:800,fontSize:18}}>{o.icon}</div>
            <div className="nm"><div className="nm-name" style={{fontSize:16}}>{o.name}</div><div className="nm-sub" style={{textTransform:"none",letterSpacing:0,fontFamily:'"Hanken Grotesk", sans-serif',fontSize:12}}>{o.sub}</div></div>
            <span>{I.chev}</span>
          </div>
        ))}
      </div>
    </Sheet>
  );
}

function BuilderScreen({ onBack }){
  const [name, setName] = useState("New workout");
  const [tag, setTag] = useState("PUSH");
  // each item: { id, name, group, equip, setList:[{reps, rir, type}] }
  const mkSets = (arr) => arr.map(([reps,rir,type])=>({reps,rir,type:type||"working"}));
  const [items, setItems] = useState([
    {...CATALOG_BY_ID["flat"], setList:mkSets([[12,0,"warmup"],[15,2],[12,2],[10,1],[8,0,"failure"]])},
    {...CATALOG_BY_ID["incline"], setList:mkSets([[15,2],[12,2],[10,1],[8,1]])},
  ]);
  const [picking, setPicking] = useState(false);
  const [openId, setOpenId] = useState(null); // expanded editor

  function addItems(picked){
    setItems(cur => {
      const existing = new Set(cur.map(i=>i.id));
      const adds = picked.filter(id=>!existing.has(id)).map(id=>({...CATALOG_BY_ID[id], setList:mkSets([[12,2],[10,2],[8,1]])}));
      return [...cur, ...adds];
    });
    setPicking(false);
  }
  function removeItem(id){ setItems(cur=>cur.filter(i=>i.id!==id)); }
  function toggleLink(idx){
    setItems(cur=>{
      if(idx>=cur.length-1) return cur;
      const copy=cur.map(x=>({...x}));
      const a=copy[idx], b=copy[idx+1];
      if(a.ssGroup!=null && a.ssGroup===b.ssGroup){ b.ssGroup=null; }
      else { const gid=a.ssGroup!=null?a.ssGroup:Math.random().toString(36).slice(2); a.ssGroup=gid; b.ssGroup=gid; }
      return copy;
    });
  }
  function updateSet(id, si, patch){ setItems(cur=>cur.map(it=>it.id!==id?it:{...it,setList:it.setList.map((s,k)=>k===si?{...s,...patch}:s)})); }
  function addSet(id){ setItems(cur=>cur.map(it=>{ if(it.id!==id) return it; const last=it.setList[it.setList.length-1]||{reps:10,rir:2,type:"working"}; return {...it,setList:[...it.setList,{reps:last.reps,rir:last.rir,type:"working"}]}; })); }
  function removeSet(id, si){ setItems(cur=>cur.map(it=>it.id!==id?it:{...it,setList:it.setList.filter((_,k)=>k!==si)})); }

  return (
    <div className="body">
      <TopBar onBack={onBack} eyebrow="NEW WORKOUT" right={I.dots} />
      <input value={name} onChange={e=>setName(e.target.value)} className="h1" style={{border:0,background:"transparent",outline:"none",color:"var(--ink)",fontSize:28,padding:0,width:"100%"}} />

      <div style={{display:"flex",gap:6,marginTop:10,flexWrap:"wrap"}}>
        {["PUSH","PULL","LEGS"].map(t=>(
          <div key={t} onClick={()=>setTag(t)} style={{cursor:"pointer",padding:"6px 12px",borderRadius:999,fontFamily:'Geist Mono, monospace',fontSize:10,letterSpacing:".14em",textTransform:"uppercase",fontWeight:600,border:"1.5px solid var(--ink)",background:tag===t?"var(--accent-2)":"transparent",color:tag===t?"var(--on-accent)":"var(--ink-soft)"}}>{t}</div>
        ))}
        <div style={{padding:"6px 12px",borderRadius:999,border:"1.5px dashed var(--ink-faint)",fontFamily:'Geist Mono, monospace',fontSize:10,letterSpacing:".14em",textTransform:"uppercase",fontWeight:600,color:"var(--ink-soft)"}}>+ TAG</div>
      </div>

      <div style={{display:"flex",justifyContent:"space-between",alignItems:"baseline",marginTop:14,marginBottom:8}}>
        <Eyebrow>EXERCISES · {items.length}</Eyebrow>
        <Eyebrow>{items.reduce((a,i)=>a+i.setList.length,0)} SETS</Eyebrow>
      </div>

      <div className="scroll" style={{gap:8}}>
        {(()=>{
          // group consecutive items sharing a non-null ssGroup
          const groups=[];
          items.forEach((it,idx)=>{
            const prev=groups[groups.length-1];
            if(it.ssGroup!=null && prev && prev.g===it.ssGroup) prev.rows.push({it,idx});
            else groups.push({g:it.ssGroup, rows:[{it,idx}]});
          });
          const SSL=["A","B","C","D"];
          const renderRow=(it,idx,ssLabel)=>{
            const repsSummary=it.setList.map(s=>s.reps).join("-");
            const hasSpecial=it.setList.some(s=>s.type!=="working");
            const canLink=idx<items.length-1;
            const linked=it.ssGroup!=null && items[idx+1] && items[idx+1].ssGroup===it.ssGroup;
            return (
              <div key={it.id}>
                <div className="row" onClick={()=>setOpenId(it.id)} style={{cursor:"pointer"}}>
                  <span style={{color:"var(--ink-faint)"}}>{I.grip}</span>
                  <div className="badge" style={ssLabel?{background:"var(--accent-2)",color:"var(--on-accent)",borderColor:"var(--accent-2)"}:{}}>{ssLabel||(idx+1)}</div>
                  <div className="nm">
                    <div className="nm-name">{it.name}</div>
                    <div className="nm-sub">{it.setList.length} sets · {repsSummary}{hasSpecial?" · MIXED":""}</div>
                  </div>
                  {canLink && (
                    <button type="button" title={linked?"Unlink superset":"Superset with next"} onClick={(e)=>{e.stopPropagation();toggleLink(idx);}} style={{appearance:"none",border:0,background:"transparent",cursor:"pointer",color:linked?"var(--accent-2)":"var(--ink-soft)",fontSize:16,padding:"0 4px",lineHeight:1}}>{linked?"⛓":"⛓\uFE0E"}</button>
                  )}
                  <button type="button" onClick={(e)=>{e.stopPropagation();removeItem(it.id);}} style={{appearance:"none",border:0,background:"transparent",cursor:"pointer",color:"var(--ink-soft)",fontFamily:'Hanken Grotesk, sans-serif',fontWeight:800,fontSize:16,padding:"0 4px"}}>✕</button>
                </div>
              </div>
            );
          };
          return groups.map((grp,gi)=>{
            if(grp.g!=null && grp.rows.length>1){
              return (
                <div key={gi} style={{border:"2px solid var(--accent-2)",borderRadius:16,padding:"8px 8px",display:"flex",flexDirection:"column",gap:6,position:"relative"}}>
                  <div style={{display:"flex",alignItems:"center",justifyContent:"space-between",padding:"0 4px 2px"}}>
                    <Eyebrow style={{color:"var(--accent-2)",fontSize:9}}>SUPERSET · {grp.rows.length} MOVES</Eyebrow>
                    <button type="button" onClick={()=>toggleLink(grp.rows[0].idx)} style={{appearance:"none",border:0,background:"transparent",cursor:"pointer",color:"var(--ink-soft)",fontFamily:'Geist Mono, monospace',fontSize:9,letterSpacing:".1em",textTransform:"uppercase",fontWeight:600}}>UNLINK</button>
                  </div>
                  {grp.rows.map((r,k)=>renderRow(r.it,r.idx,SSL[k]))}
                </div>
              );
            }
            return renderRow(grp.rows[0].it,grp.rows[0].idx,null);
          });
        })()}
        <div className="row dashed" onClick={()=>setPicking(true)} style={{justifyContent:"center",cursor:"pointer",color:"var(--accent)",fontFamily:'Hanken Grotesk, sans-serif',fontWeight:700,fontSize:14,padding:"14px 12px"}}>
          {I.plus} ADD EXERCISE
        </div>
        <div style={{textAlign:"center",padding:"4px 12px 2px",fontFamily:'"Hanken Grotesk", sans-serif',fontSize:11,color:"var(--ink-soft)",fontWeight:500}}>
          Tap ⛓ on an exercise to superset it with the one below.
        </div>
      </div>

      <div style={{display:"flex",gap:8,padding:"10px 0 18px"}}>
        <Btn kind="secondary" size="sm" onClick={onBack}>Cancel</Btn>
        <Btn size="lg" onClick={onBack} style={{flex:1}}>Save workout {I.fwd}</Btn>
      </div>

      {picking && <ExercisePickerSheet existing={items.map(i=>i.id)} onClose={()=>setPicking(false)} onAdd={addItems} />}
      {openId && (()=>{ const it = items.find(x=>x.id===openId); return it ? <SetEditorSheet item={it} onClose={()=>setOpenId(null)} updateSet={updateSet} addSet={addSet} removeSet={removeSet} /> : null; })()}
    </div>
  );
}

function SetEditorSheet({ item, onClose, updateSet, addSet, removeSet }){
  const TYPE_LABEL = {working:"Working",warmup:"Warm-up",dropset:"Drop set",failure:"To failure",amrap:"AMRAP"};
  return (
    <Sheet eyebrow={`${item.group.toUpperCase()} · ${item.setList.length} SETS`} title={item.name + "."} onClose={onClose}>
      <div className="sheet-scroll" style={{gap:8}}>
        <div style={{display:"grid",gridTemplateColumns:"30px 1fr 1fr 26px",gap:8,alignItems:"center",padding:"0 2px",marginBottom:2}}>
          <Eyebrow style={{fontSize:9}}>SET</Eyebrow>
          <Eyebrow style={{fontSize:9,textAlign:"center"}}>REPS</Eyebrow>
          <Eyebrow style={{fontSize:9,textAlign:"center"}}>RIR</Eyebrow>
          <span></span>
        </div>

        {item.setList.map((s,si)=>(
          <div key={si} style={{paddingBottom:8,borderBottom:si<item.setList.length-1?"1px solid var(--ink-faint)":"0",marginBottom:2}}>
            <div style={{display:"grid",gridTemplateColumns:"30px 1fr 1fr 26px",gap:8,alignItems:"center"}}>
              <div style={{width:30,height:30,borderRadius:8,display:"flex",alignItems:"center",justifyContent:"center",fontFamily:'Oswald, sans-serif',fontWeight:700,fontSize:14,background:s.type==="working"?"transparent":"var(--accent-2)",color:s.type==="working"?"var(--ink)":"var(--on-accent)",border:"1.5px solid "+(s.type==="working"?"var(--ink-faint)":"var(--accent-2)")}}>{si+1}</div>
              <input value={s.reps} onChange={e=>updateSet(item.id,si,{reps:e.target.value.replace(/[^0-9]/g,"")||0})} inputMode="numeric"
                style={{width:"100%",boxSizing:"border-box",textAlign:"center",background:"var(--bg)",border:"1.5px solid var(--ink-faint)",borderRadius:9,padding:"8px 4px",color:"var(--ink)",fontFamily:'Oswald, sans-serif',fontWeight:700,fontSize:18,outline:"none"}} />
              <div style={{display:"flex",alignItems:"center",justifyContent:"space-between",background:"var(--bg)",border:"1.5px solid var(--ink-faint)",borderRadius:9,padding:"0 6px",height:36}}>
                <button type="button" onClick={()=>updateSet(item.id,si,{rir:Math.max(0,s.rir-1)})} style={{appearance:"none",border:0,background:"transparent",cursor:"pointer",color:"var(--ink-soft)",fontSize:16,fontFamily:'Hanken Grotesk, sans-serif',fontWeight:800,width:20}}>−</button>
                <span style={{fontFamily:'Oswald, sans-serif',fontWeight:700,fontSize:16,color:"var(--accent)"}}>{s.rir}</span>
                <button type="button" onClick={()=>updateSet(item.id,si,{rir:Math.min(5,s.rir+1)})} style={{appearance:"none",border:0,background:"transparent",cursor:"pointer",color:"var(--ink-soft)",fontSize:16,fontFamily:'Hanken Grotesk, sans-serif',fontWeight:800,width:20}}>+</button>
              </div>
              <button type="button" onClick={()=>removeSet(item.id,si)} disabled={item.setList.length<=1} style={{appearance:"none",border:0,background:"transparent",cursor:item.setList.length<=1?"default":"pointer",color:"var(--ink-soft)",opacity:item.setList.length<=1?.3:1,fontFamily:'Hanken Grotesk, sans-serif',fontWeight:800,fontSize:15}}>✕</button>
            </div>
            <div style={{display:"flex",gap:5,flexWrap:"wrap",marginTop:6,paddingLeft:38}}>
              {Object.keys(TYPE_LABEL).map(t=>(
                <div key={t} onClick={()=>updateSet(item.id,si,{type:t})} style={{cursor:"pointer",padding:"4px 9px",borderRadius:999,fontFamily:'Geist Mono, monospace',fontSize:9,letterSpacing:".08em",textTransform:"uppercase",fontWeight:600,border:"1px solid "+(s.type===t?"var(--accent)":"var(--ink-faint)"),background:s.type===t?"var(--accent)":"transparent",color:s.type===t?"var(--on-accent)":"var(--ink-soft)"}}>{TYPE_LABEL[t]}</div>
              ))}
            </div>
          </div>
        ))}

        <div onClick={()=>addSet(item.id)} style={{cursor:"pointer",textAlign:"center",padding:"11px",borderRadius:10,border:"1.5px dashed var(--accent)",color:"var(--accent)",fontFamily:'Hanken Grotesk, sans-serif',fontWeight:700,fontSize:14,marginTop:2}}>
          + Add set
        </div>
      </div>

      <div style={{paddingTop:10,marginTop:"auto"}}>
        <Btn size="lg" onClick={onClose} style={{width:"100%"}}>Done {I.fwd}</Btn>
      </div>
    </Sheet>
  );
}

function ExercisePickerSheet({ existing, onClose, onAdd }){
  const [filter, setFilter] = useState("All");
  const [sel, setSel] = useState([]);
  const groups = ["All", ...EXERCISE_CATALOG.map(g=>g.group)];
  const shown = EXERCISE_CATALOG.filter(g => filter==="All" || g.group===filter);

  function toggle(id){ setSel(s => s.includes(id) ? s.filter(x=>x!==id) : [...s,id]); }

  return (
    <Sheet eyebrow="ADD EXERCISE" title="Pick exercises." onClose={onClose}>
      <div style={{flexShrink:0,display:"flex",alignItems:"center",gap:8,padding:"9px 14px",borderRadius:12,background:"var(--surface)",border:"1.5px solid var(--ink-faint)",marginBottom:10}}>
        <span style={{fontFamily:'Hanken Grotesk, sans-serif',fontWeight:500,fontSize:13,color:"var(--ink-soft)"}}>Search exercises…</span>
      </div>
      <div style={{flexShrink:0,display:"flex",gap:6,overflowX:"auto",overflowY:"hidden",marginBottom:10,padding:"3px 0 5px"}}>
        {groups.map((g,i)=>(
          <FilterChip key={i} on={filter===g} onClick={()=>setFilter(g)} accent>{g}</FilterChip>
        ))}
      </div>
      <div className="sheet-scroll">
        {shown.map((grp,gi)=>(
          <div key={gi}>
            <Eyebrow style={{marginBottom:6,marginTop:gi===0?0:8}}>{grp.group.toUpperCase()}</Eyebrow>
            <div style={{display:"flex",flexDirection:"column",gap:6}}>
              {grp.items.map((it,ii)=>{
                const added = existing.includes(it.id);
                const on = sel.includes(it.id);
                return (
                  <div key={ii} className="row" onClick={()=>!added && toggle(it.id)} style={{cursor:added?"default":"pointer",opacity:added?.5:1,borderColor:on?"var(--accent)":"var(--ink-faint)",borderWidth:on?2:1.5}}>
                    <div className="nm"><div className="nm-name">{it.name}</div><div className="nm-sub">{it.equip}</div></div>
                    <div style={{width:28,height:28,borderRadius:"50%",flex:"none",display:"flex",alignItems:"center",justifyContent:"center",fontFamily:'Hanken Grotesk, sans-serif',fontWeight:800,fontSize:14,border:"1.5px solid "+(on||added?"var(--accent)":"var(--ink-faint)"),background:on||added?"var(--accent)":"transparent",color:on||added?"var(--on-accent)":"var(--ink)"}}>{added?"✓":on?"✓":"+"}</div>
                  </div>
                );
              })}
            </div>
          </div>
        ))}
      </div>
      <div style={{display:"flex",gap:8,paddingTop:10,marginTop:"auto"}}>
        <Btn kind="secondary" size="sm" onClick={onClose}>Cancel</Btn>
        <Btn size="sm" onClick={()=>onAdd(sel)} style={{flex:1,opacity:sel.length?1:.5}}>{sel.length?`Add ${sel.length} selected`:"Select exercises"} {I.fwd}</Btn>
      </div>
    </Sheet>
  );
}

// ─────────────────────────────────────────────────────────────
// ROUTINE BUILDER (multi-day program)
// ─────────────────────────────────────────────────────────────
function RoutineScreen({ onBack }){
  const [name, setName] = useState("New routine");
  const [weeks, setWeeks] = useState(8);
  const [days, setDays] = useState([
    {nm:"Chest & Tris", sub:"7 exercises"},
    {nm:"Back & Bis", sub:"6 exercises"},
    {nm:"Legs", sub:"5 exercises"},
    {nm:"Rest", sub:"", rest:true},
    {nm:"Shoulders & Arms", sub:"6 exercises"},
  ]);
  const [adding, setAdding] = useState(false);
  const DOW = ["MON","TUE","WED","THU","FRI","SAT","SUN"];

  function addWorkout(w){ setDays(d=>[...d, w]); setAdding(false); }
  function removeDay(i){ setDays(d=>d.filter((_,k)=>k!==i)); }

  return (
    <div className="body">
      <TopBar onBack={onBack} eyebrow="NEW ROUTINE" right={I.dots} />
      <input value={name} onChange={e=>setName(e.target.value)} className="h1" style={{border:0,background:"transparent",outline:"none",color:"var(--ink)",fontSize:28,padding:0,width:"100%"}} />

      {/* week stepper */}
      <div style={{display:"flex",alignItems:"center",gap:10,marginTop:12}}>
        <Eyebrow style={{flex:1}}>PROGRAM LENGTH</Eyebrow>
        <IconBtn onClick={()=>setWeeks(w=>Math.max(1,w-1))} style={{width:32,height:32,fontSize:18}}>−</IconBtn>
        <div style={{fontFamily:'Oswald, sans-serif',fontWeight:700,fontSize:26,letterSpacing:"-.01em",minWidth:70,textAlign:"center",color:"var(--ink)"}}>{weeks}<span style={{fontFamily:'Hanken Grotesk, sans-serif',fontSize:11,marginLeft:3,opacity:.6,fontWeight:600}}>wks</span></div>
        <IconBtn onClick={()=>setWeeks(w=>w+1)} style={{width:32,height:32,fontSize:18}}>+</IconBtn>
      </div>

      <div style={{display:"flex",justifyContent:"space-between",alignItems:"baseline",marginTop:14,marginBottom:8}}>
        <Eyebrow>WEEKLY SPLIT</Eyebrow>
        <Eyebrow>{days.filter(d=>!d.rest).length} WORKOUTS / WK</Eyebrow>
      </div>

      <div className="scroll" style={{gap:8}}>
        {days.map((d,i)=>(
          <div key={i} className="row" style={{opacity:d.rest?.55:1,borderStyle:d.rest?"dashed":"solid"}}>
            <div className="badge">{(DOW[i]||"D")[0]}</div>
            <div className="nm"><div className="nm-name">{d.nm}</div><div className="nm-sub">{DOW[i]||`DAY ${i+1}`}{d.sub?` · ${d.sub}`:""}</div></div>
            <button type="button" onClick={()=>removeDay(i)} style={{appearance:"none",border:0,background:"transparent",cursor:"pointer",color:"var(--ink-soft)",fontFamily:'Hanken Grotesk, sans-serif',fontWeight:800,fontSize:16,padding:"0 4px"}}>✕</button>
          </div>
        ))}
        <div className="row dashed" onClick={()=>setAdding(true)} style={{justifyContent:"center",cursor:"pointer",color:"var(--accent)",fontFamily:'Hanken Grotesk, sans-serif',fontWeight:700,fontSize:14,padding:"14px 12px"}}>
          {I.plus} ADD / CREATE WORKOUT
        </div>
        <div className="row dashed" onClick={()=>addWorkout({nm:"Rest",sub:"",rest:true})} style={{justifyContent:"center",cursor:"pointer",color:"var(--ink-soft)",fontFamily:'Hanken Grotesk, sans-serif',fontWeight:600,fontSize:13,padding:"12px"}}>
          + Add rest day
        </div>
      </div>

      <div style={{display:"flex",gap:8,padding:"10px 0 18px"}}>
        <Btn kind="secondary" size="sm" onClick={onBack}>Cancel</Btn>
        <Btn size="lg" onClick={onBack} style={{flex:1}}>Save routine {I.fwd}</Btn>
      </div>

      {adding && <WorkoutPickerSheet onClose={()=>setAdding(false)} onPick={addWorkout} />}
    </div>
  );
}

const SAVED_WORKOUTS = [
  {nm:"Chest & Tris", sub:"7 exercises"},
  {nm:"Back & Bis", sub:"6 exercises"},
  {nm:"Legs", sub:"5 exercises"},
  {nm:"Shoulders", sub:"5 exercises"},
  {nm:"Arms · finisher", sub:"4 exercises"},
  {nm:"Active recovery", sub:"3 exercises"},
];

function WorkoutPickerSheet({ onClose, onPick }){
  return (
    <Sheet eyebrow="ADD TO ROUTINE" title="Add a workout." onClose={onClose}>
      {/* create new — pinned at top */}
      <div onClick={()=>onPick({nm:"New workout",sub:"0 exercises",isNew:true})} style={{flexShrink:0,display:"flex",alignItems:"center",gap:12,padding:"14px 14px",borderRadius:14,border:"2px solid var(--accent)",background:"color-mix(in oklab, var(--accent) 14%, transparent)",cursor:"pointer",marginBottom:10}}>
        <div style={{width:36,height:36,borderRadius:10,flex:"none",display:"flex",alignItems:"center",justifyContent:"center",background:"var(--accent)",color:"var(--on-accent)"}}>{I.plus}</div>
        <div className="nm"><div className="nm-name">Create new workout</div><div className="nm-sub">Build from scratch</div></div>
        <span>{I.chev}</span>
      </div>

      <Eyebrow style={{flexShrink:0,marginBottom:6}}>FROM YOUR LIBRARY</Eyebrow>
      <div className="sheet-scroll" style={{gap:6}}>
        {SAVED_WORKOUTS.map((w,i)=>(
          <div key={i} className="row" onClick={()=>onPick(w)} style={{cursor:"pointer"}}>
            <div className="nm"><div className="nm-name">{w.nm}</div><div className="nm-sub">{w.sub}</div></div>
            <div className="icon-btn" style={{width:28,height:28,fontSize:14,borderColor:"var(--accent)",color:"var(--accent)"}}>+</div>
          </div>
        ))}
      </div>
    </Sheet>
  );
}

// ─────────────────────────────────────────────────────────────
// FOLDER CREATE
// ─────────────────────────────────────────────────────────────
function FolderScreen({ onBack }){
  const [name, setName] = useState("New folder");
  const COLORS = ["#26B6F6","#FF6A1F","#00D9B8","#FFCC33","#FF4D6D","#9B6BFF"];
  const [color, setColor] = useState(COLORS[0]);
  return (
    <div className="body">
      <TopBar onBack={onBack} eyebrow="NEW FOLDER" right={I.dots} />

      <div style={{display:"flex",flexDirection:"column",alignItems:"center",marginTop:24,gap:14}}>
        <div style={{width:72,height:72,borderRadius:16,background:color,border:"2px solid var(--ink)",position:"relative",boxShadow:"0 6px 0 0 var(--ink)"}}>
          <div style={{position:"absolute",top:-7,left:14,width:34,height:11,background:color,borderTop:"2px solid var(--ink)",borderLeft:"2px solid var(--ink)",borderRight:"2px solid var(--ink)",borderRadius:"6px 6px 0 0"}}></div>
        </div>
        <input value={name} onChange={e=>setName(e.target.value)} className="h1" style={{border:0,background:"transparent",outline:"none",color:"var(--ink)",fontSize:26,padding:0,width:"100%",textAlign:"center"}} />
      </div>

      <Eyebrow style={{marginTop:24,marginBottom:10}}>FOLDER COLOR</Eyebrow>
      <div style={{display:"flex",gap:10,flexWrap:"wrap"}}>
        {COLORS.map(c=>(
          <div key={c} onClick={()=>setColor(c)} style={{cursor:"pointer",width:42,height:42,borderRadius:12,background:c,border:color===c?"2px solid var(--ink)":"1.5px solid var(--ink-faint)",boxShadow:color===c?"0 0 0 2px var(--accent-2)":"none"}}></div>
        ))}
      </div>

      <div style={{flex:1}}></div>
      <div style={{display:"flex",gap:8,padding:"10px 0 18px"}}>
        <Btn kind="secondary" size="sm" onClick={onBack}>Cancel</Btn>
        <Btn size="lg" onClick={onBack} style={{flex:1}}>Create folder {I.fwd}</Btn>
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// TAB BAR + PHONE SHELL
// ─────────────────────────────────────────────────────────────
function TabBar({ tab, setTab }){
  const tabs = [["today",I.bolt,"Today"],["library",I.lib,"Library"],["plan",I.cal,"Plan"],["you",I.user,"You"]];
  return (
    <div className="tabbar">
      {tabs.map(([k,ic,lbl]) => (
        <button key={k} type="button" className={"tab"+(tab===k?" on":"")} onClick={()=>setTab(k)}>
          <div className="tab-icon">{ic}</div>
          <span>{lbl}</span>
        </button>
      ))}
    </div>
  );
}

function StatusBar(){
  return (
    <div className="statusbar">
      <span>9:41</span>
      <span className="right"><span>5G</span><span className="bat"></span></span>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// APP
// ─────────────────────────────────────────────────────────────
function App(){
  const [palette, setPalette] = useState(()=>{ try{return localStorage.getItem("pulse-pal")||"coastal";}catch(e){return "coastal";} });
  useEffect(()=>{ try{localStorage.setItem("pulse-pal",palette);}catch(e){} }, [palette]);

  const [tab, setTab] = useState("today");
  // overlay stack for non-tab screens: program, stats, prs, history, session-detail
  const [stack, setStack] = useState([]);
  // workout session: null = not in workout; else { stepIdx, phase }
  const [session, setSession] = useState(null);
  const [swaps, setSwaps] = useState({});       // exIdx -> alternative
  const [doneSteps, setDoneSteps] = useState([]); // completed step indices
  const [sheet, setSheet] = useState(null);     // active-workout sheet: swap|history|jump

  const go = (screen) => setStack(s => [...s, screen]);
  const back = () => setStack(s => s.slice(0,-1));
  const overlay = stack[stack.length-1];

  function startWorkout(){
    setStack([]);
    setSwaps({}); setDoneSteps([]);
    setSession({ stepIdx:0, phase:"pre" });
  }
  function beginSets(){ setSession(s => ({...s, phase:"active"})); }
  function logSet(){
    const step = STEPS[session.stepIdx];
    const isFinal = session.stepIdx === STEPS.length - 1;
    setDoneSteps(d => d.includes(session.stepIdx) ? d : [...d, session.stepIdx]);
    if (isFinal){ setSession(s=>({...s, phase:"summary"})); }
    else if (step.rest){ setSession(s=>({...s, phase:"rest"})); }
    else { setSession(s=>({...s, stepIdx:s.stepIdx+1, phase:"active"})); } // straight to superset partner
  }
  function afterRest(){
    setSession(s => ({...s, stepIdx:Math.min(s.stepIdx+1, STEPS.length-1), phase:"active"}));
  }
  function swapExercise(exIdx, alt){ setSwaps(s => ({...s, [exIdx]:alt})); }
  function jumpToExercise(targetExIdx){
    const idxs = EX_STEPS[targetExIdx] || [];
    const next = idxs.find(i => !doneSteps.includes(i));
    setSession(s => ({...s, stepIdx: next != null ? next : (idxs[0] ?? s.stepIdx), phase:"active"}));
  }
  function endWorkout(){ setSession(null); setTab("today"); }

  // ----- render body -----
  let body, showTabs = true;

  if (session){
    showTabs = false;
    const curStep = STEPS[session.stepIdx];
    const isFinal = session.stepIdx === STEPS.length - 1;
    const nextStep = STEPS[session.stepIdx + 1] || null;
    if (session.phase==="pre") body = <PreworkoutScreen onStart={beginSets} onBack={endWorkout} />;
    else if (session.phase==="active") body = <ActiveScreen step={curStep} isFinal={isFinal} swaps={swaps} doneSteps={doneSteps} onLogSet={logSet} onSkip={afterRest} onPause={endWorkout} onOpenSheet={setSheet} />;
    else if (session.phase==="rest") body = <RestScreen nextExIdx={nextStep?nextStep.exIdx:null} nextSetIdx={nextStep?nextStep.setIdx:0} onDone={afterRest} />;
    else if (session.phase==="summary") body = <SummaryScreen onDone={endWorkout} go={go} />;
  } else if (overlay){
    showTabs = overlay==="program" ? false : false;
    if (overlay==="program") body = <ProgramScreen onBack={back} go={go} onStartWorkout={startWorkout} />;
    else if (overlay==="stats") body = <StatsScreen onBack={back} />;
    else if (overlay==="prs") body = <PRScreen onBack={back} />;
    else if (overlay==="history") body = <HistoryScreen onBack={back} go={go} />;
    else if (overlay==="session-detail") body = <SessionDetailScreen onBack={back} />;
    else if (overlay.startsWith("exdetail:")) body = <ExerciseDetailScreen exId={overlay.slice(9)} onBack={back} />;
    else if (overlay==="builder") body = <BuilderScreen onBack={back} />;
    else if (overlay==="routine") body = <RoutineScreen onBack={back} />;
    else if (overlay==="folder") body = <FolderScreen onBack={back} />;
  } else {
    if (tab==="today") body = <TodayScreen onStartWorkout={startWorkout} go={go} />;
    else if (tab==="library") body = <LibraryScreen go={go} />;
    else if (tab==="plan") body = <PlanScreen go={go} onStartWorkout={startWorkout} />;
    else if (tab==="you") body = <YouScreen go={go} palette={palette} setPalette={setPalette} />;
  }

  return (
    <div className="stage">
      <div className="brand"><span className="brand-dot"></span><span>Pulse Gym</span></div>

      {/* palette toggle */}
      <div className="pal-toggle">
        {Object.keys(PALETTES).map(k => (
          <button key={k} type="button" className={palette===k?"on":""} onClick={()=>setPalette(k)}>
            <span className="sw" style={{background:PALETTES[k].accent}}></span>{PALETTES[k].label}
          </button>
        ))}
      </div>

      <div className="phone" style={paletteVars(PALETTES[palette])}>
        <div className="notch"></div>
        <div className="screen">
          <StatusBar />
          <div className="screen-anim" key={session?session.phase+session.stepIdx:overlay||tab} style={{flex:1,display:"flex",flexDirection:"column",minHeight:0}}>
            {body}
          </div>
          {session && session.phase==="active" && sheet && (()=>{
            const ex = TODAY_WORKOUT.exercises[STEPS[session.stepIdx].exIdx];
            const exIdx = STEPS[session.stepIdx].exIdx;
            if (sheet==="swap") return <SwapSheet ex={ex} onClose={()=>setSheet(null)} onPick={(a)=>{ swapExercise(exIdx,a); setSheet(null); }} />;
            if (sheet==="history") return <HistorySheet ex={ex} onClose={()=>setSheet(null)} />;
            if (sheet==="jump") return <JumpSheet curExIdx={exIdx} doneSteps={doneSteps} swaps={swaps} onClose={()=>setSheet(null)} onJump={(t)=>{ jumpToExercise(t); setSheet(null); }} />;
            return null;
          })()}
          {showTabs && <TabBar tab={tab} setTab={(t)=>{setStack([]);setTab(t);}} />}
        </div>
      </div>
    </div>
  );
}

ReactDOM.createRoot(document.getElementById("root")).render(<App />);
