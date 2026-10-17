import React from 'react';
import { render, screen, fireEvent } from '@testing-library/react';
import Board, {type RecordedPiece} from '@/components/progress/RecordedBoard';
const piece:RecordedPiece={ownerUid:'a',slot:0,completionId:'fixture-completion',source:'check_in',unlockedAt:'2026-10-18T10:00:00.000Z'};
it('renders 25 accessible recorded slots and details without issuing or inventing legacy unlocks',()=>{
  render(<Board ownerUid="a" pieces={[piece]} legacyTotal={7}/>);
  expect(screen.getAllByRole('button')).toHaveLength(25);
  expect(screen.getByRole('button',{name:'Slot 1: recorded unlock'})).toBeInTheDocument();
  fireEvent.click(screen.getByRole('button',{name:'Slot 2: not unlocked'}));expect(screen.getByText('No recorded unlock for this slot.')).toBeInTheDocument();
  expect(screen.getByText(/Not converted into board unlocks/)).toBeInTheDocument();
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
