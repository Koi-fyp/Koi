import React from 'react';
import { render,screen,fireEvent,waitFor } from '@testing-library/react';
import Controls,{type VoiceCaptureAdapter} from '@/components/voice/VoiceCaptureControls';
import type {CaptureSnapshot} from '@/lib/speech/MicrophoneCapture';
const capture:CaptureSnapshot={state:'ready',blob:new Blob(['fixture'],{type:'audio/webm'}),mimeType:'audio/webm',error:null,permission:'granted',inputs:[],durationMs:1000,bytes:7,input:null};
const adapter=():VoiceCaptureAdapter=>({record:jest.fn(async()=>{}),stop:jest.fn(),cancel:jest.fn(),submitDirect:jest.fn(async()=>{})});
it('does not request permissions or submit on mount and ships disabled by default',()=>{
  const a=adapter();render(<Controls ownerUid="fixture" companionId="aisha" capture={capture} adapter={a}/>);
  expect(screen.getByRole('button',{name:'Record'})).toBeDisabled();expect(a.record).not.toHaveBeenCalled();expect(a.submitDirect).not.toHaveBeenCalled();
});
it('direct send is single-flight and owner/generation change aborts and releases the old adapter',async()=>{
  const a=adapter();let signal:AbortSignal|undefined;
  a.submitDirect=jest.fn((_value,provided)=>{signal=provided;return new Promise(()=>{});});
  const view=render(<Controls ownerUid="fixture-a" companionId="aisha" capture={capture} captureOwnerUid="fixture-a" captureCompanionId="aisha" adapter={a} enabled/>);
  const send=screen.getByRole('button',{name:'Submit recording directly'});fireEvent.click(send);fireEvent.click(send);expect(a.submitDirect).toHaveBeenCalledTimes(1);
  view.rerender(<Controls ownerUid="fixture-b" companionId="raza" capture={null} adapter={a} enabled/>);
  expect(signal?.aborted).toBe(true);expect(a.cancel).toHaveBeenCalled();expect(a.record).not.toHaveBeenCalled();
  await waitFor(()=>expect(screen.queryByText('Submitting the recording…')).toBeNull());
});

it('cannot submit a stale recording belonging to another owner or companion',()=>{
  const a=adapter();render(<Controls ownerUid="new-owner" companionId="raza" capture={capture} captureOwnerUid="old-owner" captureCompanionId="aisha" adapter={a} enabled/>);
  expect(screen.getByRole('button',{name:'Submit recording directly'})).toBeDisabled();expect(a.submitDirect).not.toHaveBeenCalled();
});
