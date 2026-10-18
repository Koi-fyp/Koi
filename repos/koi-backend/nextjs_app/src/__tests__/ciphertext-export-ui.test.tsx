import React from 'react';
import { render,screen,fireEvent,waitFor } from '@testing-library/react';
import { TextEncoder } from 'util';
let mockOwner='owner-a';const mockRead=jest.fn(),mockCurrent={pending:false};
jest.mock('@/contexts/AuthContext',()=>({useAuth:()=>({user:{uid:mockOwner},loading:false})}));
jest.mock('@/contexts/ConversationContext',()=>({useSharedConversation:()=>({uid:mockOwner,session:{getSnapshot:()=>mockCurrent}})}));
jest.mock('@/lib/firebase',()=>({auth:{get currentUser(){return {uid:mockOwner};}}}));
jest.mock('@/lib/data-portability/ciphertextExport',()=>({...jest.requireActual('@/lib/data-portability/ciphertextExport'),readCiphertextExport:(...args:unknown[])=>mockRead(...args)}));
import Export from '@/components/data-portability/CiphertextExport';
const value={kind:'koi-ciphertext-data-export',formatVersion:1,ownerUid:'owner-a',exportedAt:'2026-10-18T10:00:00.000Z',restorationSupported:false,counts:{messages:2,conversationSnapshots:1},messages:[],conversationSnapshots:[]};
beforeAll(()=>{Object.assign(globalThis,{TextEncoder});});
beforeEach(()=>{mockOwner='owner-a';mockCurrent.pending=false;mockRead.mockReset().mockResolvedValue(value);});
it('requires consent before preparing and never claims a report or restorable backup',async()=>{
  render(<Export/>);expect(screen.getByRole('button',{name:'Prepare data export'})).toBeDisabled();
  fireEvent.click(screen.getByRole('checkbox'));fireEvent.click(screen.getByRole('button',{name:'Prepare data export'}));
  await screen.findByRole('button',{name:'Download ciphertext data JSON'});expect(screen.getByText(/No wellness report was generated/)).toBeInTheDocument();
  expect(mockRead).toHaveBeenCalledTimes(1);
});
it('blocks a streaming preparation before reading and offers truthful failure state',async()=>{
  mockCurrent.pending=true;render(<Export/>);fireEvent.click(screen.getByRole('checkbox'));fireEvent.click(screen.getByRole('button',{name:'Prepare data export'}));
  expect(await screen.findByRole('alert')).toHaveTextContent('Wait for the current reply');expect(mockRead).not.toHaveBeenCalled();
});
it('hides a prepared previous-account export immediately on account change',async()=>{
  const view=render(<Export/>);fireEvent.click(screen.getByRole('checkbox'));fireEvent.click(screen.getByRole('button',{name:'Prepare data export'}));await screen.findByRole('button',{name:/Download ciphertext/});
  mockOwner='owner-b';view.rerender(<Export/>);expect(screen.queryByRole('button',{name:/Download ciphertext/})).toBeNull();expect(screen.getByRole('checkbox')).not.toBeChecked();
});
it('does not show a late prepared result after owner change',async()=>{
  let resolve!:(v:unknown)=>void;mockRead.mockImplementation(()=>new Promise(r=>{resolve=r;}));
  const view=render(<Export/>);fireEvent.click(screen.getByRole('checkbox'));fireEvent.click(screen.getByRole('button',{name:'Prepare data export'}));
  await waitFor(()=>expect(mockRead).toHaveBeenCalledTimes(1));mockOwner='owner-b';view.rerender(<Export/>);resolve(value);
  await waitFor(()=>expect(screen.queryByRole('button',{name:/Download ciphertext/})).toBeNull());
});
