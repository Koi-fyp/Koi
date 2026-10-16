import { notFound } from 'next/navigation';
import VoiceLab from './VoiceLab';
export default function Page() { if (process.env.NODE_ENV !== 'development') notFound(); return <VoiceLab />; }
