import React, { useState } from 'react';
import { render, screen, fireEvent, within } from '@testing-library/react';
import Picker from '@/app/(authenticated)/settings/components/AvatarPicker';
function Harness() {
  const [open,setOpen]=useState(false);
  return <><button onClick={()=>setOpen(true)}>Choose companion</button><Picker isOpen={open} onClose={()=>setOpen(false)} currentAvatar="aisha" onSave={async()=>false}/></>;
}
it('names the dialog, exposes current selection, traps Tab and restores focus after Escape', () => {
  render(<Harness />);const opener=screen.getByRole('button',{name:'Choose companion'});opener.focus();fireEvent.click(opener);
  const dialog=screen.getByRole('dialog',{name:'Choose Your Companion'}), controls=within(dialog).getAllByRole('button');
  expect(controls[0]).toHaveFocus();expect(within(dialog).getByRole('button',{name:/Aisha/})).toHaveAttribute('aria-pressed','true');
  controls.at(-1)!.focus();fireEvent.keyDown(document,{key:'Tab'});expect(controls[0]).toHaveFocus();
  fireEvent.keyDown(document,{key:'Tab',shiftKey:true});expect(controls.at(-1)).toHaveFocus();
  fireEvent.keyDown(document,{key:'Escape'});expect(screen.queryByRole('dialog')).toBeNull();expect(opener).toHaveFocus();
});
