import { notFound } from 'next/navigation';
import SpeechLab from './SpeechLab';
export default function SpeechLabPage() {
  if (process.env.NODE_ENV !== 'development') notFound();
  return <SpeechLab />;
}
