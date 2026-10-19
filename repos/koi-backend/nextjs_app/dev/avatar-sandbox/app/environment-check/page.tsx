import { notFound } from 'next/navigation';
import '@/app/globals.css';
import EnvironmentCheck from './EnvironmentCheck';

export default function Page() {
  if (process.env.NODE_ENV !== 'development') notFound();
  return <EnvironmentCheck />;
}
