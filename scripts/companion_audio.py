"""Quiet original UI taps and short vowel-like companion babble; reproducible PCM."""
import math,random,struct,wave
from pathlib import Path
out=Path(__file__).resolve().parents[1]/'apps/devcat_flutter/assets/audio'
for kind in ['tyk','voice']:
 for variant in range(6):
  rng=random.Random(401+variant);rate=22050;duration=.07+variant*.004 if kind=='tyk' else .7+variant*.07;data=[]
  for i in range(int(rate*duration)):
   t=i/rate
   if kind=='tyk':
    envelope=(1-math.exp(-t*1100))*math.exp(-t*70)*(min(1,(duration-t)*250))
    value=(math.sin(2*math.pi*(290+variant*35)*t)+.18*rng.uniform(-1,1))*envelope*.18
   else:
    local=t%.15;envelope=(math.sin(math.pi*min(1,local/.11))**2 if local<.11 else 0)*min(1,(duration-t)*40)
    pitch=170+variant*18+22*math.sin(t*21)
    value=(math.sin(2*math.pi*pitch*t)+.25*math.sin(2*math.pi*pitch*2*t)+.12*math.sin(2*math.pi*(700+variant*90)*t))*envelope*.095
   data.append(struct.pack('<h',int(max(-.3,min(.3,value))*32767)))
  with wave.open(str(out/f'companion_{kind}_{variant}.wav'),'wb') as f:f.setparams((1,2,rate,0,'NONE','not compressed'));f.writeframes(b''.join(data))
