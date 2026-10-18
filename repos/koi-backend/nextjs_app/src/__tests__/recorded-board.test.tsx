import React from 'react';
import { render, screen, fireEvent } from '@testing-library/react';
import Board, {type RecordedPiece} from '@/components/progress/RecordedBoard';
const piece:RecordedPiece={ownerUid:'a',slot:0,completionId:'fixture-completion',source:'check_in',unlockedAt:'2026-10-18T10:00:00.000Z'};
it('renders 25 accessible recorded slots and details without issuing or inventing legacy unlocks',()=>{
  render(<Board ownerUid="a" pieces={[piece]} legacyTotal={7}/>);
  expect(screen.getAllByRole('button',{name:/Slot /})).toHaveLength(25);
  expect(screen.getByRole('button',{name:'Slot 1: recorded unlock'})).toBeInTheDocument();
  fireEvent.click(screen.getByRole('button',{name:'Slot 2: not unlocked'}));expect(screen.getByText('No recorded unlock for this slot.')).toBeInTheDocument();
  expect(screen.getByText(/Not converted into board unlocks/)).toBeInTheDocument();
});
it('opens an accessible milestone detail without inventing an unlock; Escape restores focus',()=>{
  render(<Board ownerUid="a" pieces={[]}/>);
  const trigger=screen.getByRole('button',{name:'Milestone 5: not unlocked'});trigger.focus();fireEvent.click(trigger);
  expect(screen.getByRole('dialog',{name:'Milestone: 5 pieces'})).toBeInTheDocument();
  expect(screen.getByText('No saved milestone receipt for this threshold.')).toBeInTheDocument();
  fireEvent.keyDown(document,{key:'Escape'});expect(screen.queryByRole('dialog')).toBeNull();expect(trigger).toHaveFocus();
});
it.each<[string,RecordedPiece[]|null]>([['missing',null],['duplicate',[piece,{...piece,slot:1}]],['foreign',[{...piece,ownerUid:'b'}]],['invalid-slot',[{...piece,slot:25}]]])('fails closed for unavailable, duplicate or foreign events: %s',(_name,pieces)=>{
  render(<Board ownerUid="a" pieces={pieces}/>);
  expect(screen.queryByRole('button',{name:/recorded unlock/})).toBeNull();
  expect(screen.getByRole('status')).toHaveTextContent('unavailable or unverified');
});
it('does not carry selection or recorded pieces across owner changes',()=>{
  const view=render(<Board ownerUid="a" pieces={[piece]}/>);fireEvent.click(screen.getByRole('button',{name:'Slot 1: recorded unlock'}));
  view.rerender(<Board ownerUid="b" pieces={[]}/>);expect(screen.queryByText(/Recorded check_in/)).toBeNull();
  expect(screen.getByRole('status')).toHaveTextContent('0 of 25 recorded slots');
});

it('unlocks milestones only from saved milestone receipts, not piece count alone',()=>{
 const pieces=Array.from({length:5},(_,i)=>({...piece,slot:i,completionId:`completion-${i}`}));
 const view=render(<Board ownerUid="a" pieces={pieces} milestones={[]}/>);
 expect(screen.getByRole('button',{name:'Milestone 5: not unlocked'})).toBeInTheDocument();
 view.rerender(<Board ownerUid="a" pieces={pieces} milestones={[5]}/>);
 fireEvent.click(screen.getByRole('button',{name:'Milestone 5: recorded milestone unlocked'}));
 expect(screen.getByText('Milestone 5 is permanently unlocked by a saved milestone receipt.')).toBeInTheDocument();
});

it('existing milestone timeline uses saved receipts, exact thresholds and the same accessible detail dialog',()=>{
 const pieces=Array.from({length:5},(_,i)=>({...piece,slot:i,completionId:`event-${i}`}));
 const view=render(<Board ownerUid="a" pieces={pieces} milestones={[]}/>);
 expect(screen.getByText('0 of 5 unlocked')).toBeInTheDocument();
 expect(screen.getAllByRole('button',{name:/Milestone timeline .*: locked/})).toHaveLength(5);
 view.rerender(<Board ownerUid="a" pieces={pieces} milestones={[5]}/>);
 const trigger=screen.getByRole('button',{name:'Milestone timeline 5: unlocked'});trigger.focus();fireEvent.keyDown(trigger,{key:'Enter'});
 expect(screen.getByRole('dialog',{name:'Milestone: 5 pieces'})).toBeInTheDocument();
 expect(screen.getByText('1 of 5 unlocked')).toBeInTheDocument();
 fireEvent.keyDown(document,{key:'Escape'});expect(trigger).toHaveFocus();
 expect(screen.queryByText(/7-Day Streak|50 Pieces|First Conversation/)).toBeNull();
});
