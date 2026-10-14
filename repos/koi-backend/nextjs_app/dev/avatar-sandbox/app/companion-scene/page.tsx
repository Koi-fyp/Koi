import { notFound } from 'next/navigation';
import MockCompanionSession from './MockCompanionSession';
export default function CompanionSandbox() {
  if (process.env.NODE_ENV !== 'development') notFound();
  return <MockCompanionSession />;
}
