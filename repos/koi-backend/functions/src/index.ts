import { initializeApp } from 'firebase-admin/app';

initializeApp();

export { sendMessage } from './functions/chat';
