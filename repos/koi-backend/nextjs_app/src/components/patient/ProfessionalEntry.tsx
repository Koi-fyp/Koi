import NeoCard from '@/components/ui/NeoCard';
import CareLink from '@/components/platform/CareLink';

export default function ProfessionalEntry() {
  return <NeoCard className="professional-card professional-narrow">
    <h2>Professional registration is not available yet</h2>
    <p>KOI Care does not currently offer public psychologist registration or an online verification application. This entry does not change your account access.</p>
    <p>Already verified? Use your existing registered care account to open professional access. The server checks verification and practice permissions before opening the workspace.</p>
    <div className="care-account-actions"><CareLink variant="primary" href="/account?entry=psychologist">Professional sign-in / access</CareLink><CareLink variant="secondary" href="/patient">Back to Care Home</CareLink></div>
  </NeoCard>;
}
