import { notFound } from 'next/navigation';
import MockChatSession from './MockChatSession';
export default function Page() { if (process.env.NODE_ENV !== 'development') notFound(); return <MockChatSession />; }
