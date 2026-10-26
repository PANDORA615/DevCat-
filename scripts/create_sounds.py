"""Original low-amplitude sine chimes; no third-party samples."""
import math, struct, wave
from pathlib import Path
root=Path(__file__).resolve().parents[1]/'apps/devcat_flutter/assets/audio'
for name,notes,length in [('tap',[(880,0),(1320,.012)],.10),('success',[(659,0),(880,.07),(1109,.14)],.46),('error',[(440,0),(392,.08)],.30)]:
 samples=[]
 for i in range(int(44100*length)):
  t=i/44100
  v=0
  for hz,start in notes:
   u=t-start
   if u>=0: v+=math.sin(2*math.pi*hz*u)*(1-math.exp(-u*400))*math.exp(-u*18)*.12/len(notes)
  v*=min(1,(length-t)*100)
  samples.append(struct.pack('<h',int(v*32767)))
 with wave.open(str(root/f'{name}.wav'),'wb') as f:
  f.setparams((1,2,44100,0,'NONE','not compressed'));f.writeframes(b''.join(samples))
