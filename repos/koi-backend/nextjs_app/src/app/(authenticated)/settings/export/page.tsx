'use client';

import { useState } from 'react';
import BackButton from '../components/BackButton';

export default function ExportPage() {
  const [isExporting, setIsExporting] = useState(false);
  const [progress, setProgress] = useState(0);
  const [exportComplete, setExportComplete] = useState(false);
  const [pdfBlob, setPdfBlob] = useState<Blob | null>(null);

  const generatePDF = async () => {
    setIsExporting(true);
    setProgress(0);
    setExportComplete(false);

    // Simulate progress while compiling report data
    const progressInterval = setInterval(() => {
      setProgress(prev => {
        if (prev >= 100) {
          clearInterval(progressInterval);
          return 100;
        }
        return prev + 2;
      });
    }, 50);

    // Wait for progress to complete
    setTimeout(async () => {
      // Dynamically import html2pdf
      const html2pdf = (await import('html2pdf.js')).default;

      // Fetch user data (replace with actual data fetching)
      const wellnessData = {
        reportDate: new Date().toLocaleDateString('en-US', {
          year: 'numeric',
          month: 'long',
          day: 'numeric'
        }),
        timeRange: 'Last 30 Days',

        // Mood data
        moodTrend: '+12%',
        averageMood: 7.2,
        moodEntries: 24,
        moodData: [
          { date: 'Week 1', score: 6.5 },
          { date: 'Week 2', score: 6.8 },
          { date: 'Week 3', score: 7.0 },
          { date: 'Week 4', score: 7.4 },
        ],

        // Loneliness data
        lonelinessScore: 6.2,
        connectionRating: 7.5,
        lonelinessData: [
          { date: 'Week 1', score: 5.8 },
          { date: 'Week 2', score: 6.0 },
          { date: 'Week 3', score: 6.4 },
          { date: 'Week 4', score: 6.2 },
        ],

        // Conversation themes
        conversationThemes: [
          { theme: 'Work & Career', count: 12, percentage: 30 },
          { theme: 'Relationships', count: 8, percentage: 20 },
          { theme: 'Personal Growth', count: 7, percentage: 17.5 },
          { theme: 'Health & Wellness', count: 6, percentage: 15 },
          { theme: 'Family', count: 5, percentage: 12.5 },
          { theme: 'Hobbies', count: 2, percentage: 5 },
        ],

        // Activity data
        totalConversations: 40,
        checkInsCompleted: 24,
        currentStreak: 12,
        longestStreak: 15,
        totalMessages: 487,

        // Crisis events
        crisisEvents: [
          {
            date: '2025-04-15',
            severity: 'Moderate',
            resourcesProvided: ['Umang Mental Health Helpline', 'Breathing Exercise'],
            resolved: true
          },
          {
            date: '2025-04-28',
            severity: 'Low',
            resourcesProvided: ['Rozan Counselling', 'Coping Strategies'],
            resolved: true
          }
        ],

        // Key insights
        insights: [
          'Your mood has improved by 12% over the past month',
          'You maintained a 12-day conversation streak',
          'Work-related discussions were your most common theme',
          'Your connection ratings show positive progression',
        ]
      };

      // Create a temporary container for HTML content
      const container = document.createElement('div');
      container.innerHTML = `
        <div style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; line-height: 1.6; color: #1a1a1a; padding: 30px;">
          <!-- Header -->
          <div style="text-align: center; margin-bottom: 30px; padding-bottom: 20px; border-bottom: 4px solid #2D63EB;">
            <div style="width: 50px; height: 50px; background: #2D63EB; border-radius: 10px; display: inline-flex; align-items: center; justify-content: center; color: white; font-weight: 900; font-size: 28px; margin-bottom: 12px; border: 2.5px solid #000;">K</div>
            <h1 style="font-size: 32px; font-weight: 900; color: #000; margin: 8px 0; letter-spacing: -0.02em;">Wellness Report</h1>
            <div style="font-size: 14px; color: #666;">Your Mental Health Journey with KOI</div>
          </div>

          <!-- Meta Info -->
          <div style="display: flex; justify-content: space-around; margin-bottom: 30px; padding: 15px; background: #F9F9F9; border: 2px solid #E5E5E5; border-radius: 10px;">
            <div style="text-align: center;">
              <div style="font-size: 11px; color: #999; text-transform: uppercase; letter-spacing: 0.05em; margin-bottom: 4px;">Report Date</div>
              <div style="font-size: 16px; font-weight: 700; color: #000;">${wellnessData.reportDate}</div>
            </div>
            <div style="text-align: center;">
              <div style="font-size: 11px; color: #999; text-transform: uppercase; letter-spacing: 0.05em; margin-bottom: 4px;">Time Period</div>
              <div style="font-size: 16px; font-weight: 700; color: #000;">${wellnessData.timeRange}</div>
            </div>
            <div style="text-align: center;">
              <div style="font-size: 11px; color: #999; text-transform: uppercase; letter-spacing: 0.05em; margin-bottom: 4px;">Conversations</div>
              <div style="font-size: 16px; font-weight: 700; color: #000;">${wellnessData.totalConversations}</div>
            </div>
          </div>

          <!-- Mood Trends Section -->
          <div style="margin-bottom: 30px;">
            <div style="display: flex; align-items: center; gap: 10px; margin-bottom: 15px; padding-bottom: 10px; border-bottom: 2.5px solid #000;">
              <div style="width: 35px; height: 35px; background: #FFD100; border: 2px solid #000; border-radius: 7px; display: flex; align-items: center; justify-content: center; font-size: 18px;">📊</div>
              <h2 style="font-size: 20px; font-weight: 800; color: #000; margin: 0;">Mood Trends</h2>
            </div>

            <div style="background: #fff; border: 2px solid #000; border-radius: 10px; padding: 20px; margin-bottom: 15px; box-shadow: 3px 3px 0 #000;">
              <div style="display: flex; justify-content: space-between; padding: 12px 0; border-bottom: 1px solid #E5E5E5;">
                <span style="font-size: 13px; color: #666; font-weight: 500;">Average Mood Score</span>
                <span style="font-size: 18px; font-weight: 700; color: #2D63EB;">${wellnessData.averageMood}/10</span>
              </div>
              <div style="display: flex; justify-content: space-between; padding: 12px 0; border-bottom: 1px solid #E5E5E5;">
                <span style="font-size: 13px; color: #666; font-weight: 500;">Trend (30 days)</span>
                <span style="font-size: 18px; font-weight: 700; color: #2DD36F;">${wellnessData.moodTrend}</span>
              </div>
              <div style="display: flex; justify-content: space-between; padding: 12px 0;">
                <span style="font-size: 13px; color: #666; font-weight: 500;">Total Entries</span>
                <span style="font-size: 18px; font-weight: 700; color: #2D63EB;">${wellnessData.moodEntries}</span>
              </div>
            </div>

            <div style="background: #fff; border: 2px solid #000; border-radius: 10px; padding: 20px; box-shadow: 3px 3px 0 #000;">
              <h3 style="margin-bottom: 12px; font-size: 14px; font-weight: 700;">Weekly Progression</h3>
              ${wellnessData.moodData.map(entry => `
                <div style="margin-bottom: 10px;">
                  <div style="display: flex; justify-content: space-between; margin-bottom: 5px; font-size: 13px;">
                    <span>${entry.date}</span>
                    <span><strong>${entry.score}/10</strong></span>
                  </div>
                  <div style="height: 20px; background: #F0F0F0; border: 2px solid #000; border-radius: 5px; overflow: hidden;">
                    <div style="height: 100%; width: ${(entry.score / 10) * 100}%; background: linear-gradient(90deg, #2D63EB 0%, #06b6d4 100%);"></div>
                  </div>
                </div>
              `).join('')}
            </div>
          </div>

          <!-- Loneliness Tracking Section -->
          <div style="margin-bottom: 30px;">
            <div style="display: flex; align-items: center; gap: 10px; margin-bottom: 15px; padding-bottom: 10px; border-bottom: 2.5px solid #000;">
              <div style="width: 35px; height: 35px; background: #FFD100; border: 2px solid #000; border-radius: 7px; display: flex; align-items: center; justify-content: center; font-size: 18px;">💙</div>
              <h2 style="font-size: 20px; font-weight: 800; color: #000; margin: 0;">Loneliness & Connection</h2>
            </div>

            <div style="background: #fff; border: 2px solid #000; border-radius: 10px; padding: 20px; margin-bottom: 15px; box-shadow: 3px 3px 0 #000;">
              <div style="display: flex; justify-content: space-between; padding: 12px 0; border-bottom: 1px solid #E5E5E5;">
                <span style="font-size: 13px; color: #666; font-weight: 500;">Loneliness Score</span>
                <span style="font-size: 18px; font-weight: 700; color: #2D63EB;">${wellnessData.lonelinessScore}/10</span>
              </div>
              <div style="display: flex; justify-content: space-between; padding: 12px 0;">
                <span style="font-size: 13px; color: #666; font-weight: 500;">Connection Rating</span>
                <span style="font-size: 18px; font-weight: 700; color: #2DD36F;">${wellnessData.connectionRating}/10</span>
              </div>
            </div>

            <div style="background: #fff; border: 2px solid #000; border-radius: 10px; padding: 20px; box-shadow: 3px 3px 0 #000;">
              <h3 style="margin-bottom: 12px; font-size: 14px; font-weight: 700;">Weekly Tracking</h3>
              ${wellnessData.lonelinessData.map(entry => `
                <div style="margin-bottom: 10px;">
                  <div style="display: flex; justify-content: space-between; margin-bottom: 5px; font-size: 13px;">
                    <span>${entry.date}</span>
                    <span><strong>${entry.score}/10</strong></span>
                  </div>
                  <div style="height: 20px; background: #F0F0F0; border: 2px solid #000; border-radius: 5px; overflow: hidden;">
                    <div style="height: 100%; width: ${(entry.score / 10) * 100}%; background: linear-gradient(90deg, #06b6d4 0%, #2D63EB 100%);"></div>
                  </div>
                </div>
              `).join('')}
            </div>
          </div>

          <!-- Conversation Themes Section -->
          <div style="margin-bottom: 30px;">
            <div style="display: flex; align-items: center; gap: 10px; margin-bottom: 15px; padding-bottom: 10px; border-bottom: 2.5px solid #000;">
              <div style="width: 35px; height: 35px; background: #FFD100; border: 2px solid #000; border-radius: 7px; display: flex; align-items: center; justify-content: center; font-size: 18px;">💭</div>
              <h2 style="font-size: 20px; font-weight: 800; color: #000; margin: 0;">Conversation Themes</h2>
            </div>

            <div style="background: #fff; border: 2px solid #000; border-radius: 10px; padding: 20px; box-shadow: 3px 3px 0 #000;">
              ${wellnessData.conversationThemes.map(theme => `
                <div style="display: flex; justify-content: space-between; align-items: center; padding: 10px; margin-bottom: 7px; background: #F9F9F9; border: 1px solid #E5E5E5; border-radius: 7px;">
                  <span style="font-weight: 600; color: #000; font-size: 13px;">${theme.theme}</span>
                  <span style="font-size: 12px; color: #666;">${theme.count} conversations (${theme.percentage}%)</span>
                </div>
              `).join('')}
            </div>
          </div>

          <!-- Activity Progress Section -->
          <div style="margin-bottom: 30px;">
            <div style="display: flex; align-items: center; gap: 10px; margin-bottom: 15px; padding-bottom: 10px; border-bottom: 2.5px solid #000;">
              <div style="width: 35px; height: 35px; background: #FFD100; border: 2px solid #000; border-radius: 7px; display: flex; align-items: center; justify-content: center; font-size: 18px;">🎯</div>
              <h2 style="font-size: 20px; font-weight: 800; color: #000; margin: 0;">Activity Progress</h2>
            </div>

            <div style="background: #fff; border: 2px solid #000; border-radius: 10px; padding: 20px; box-shadow: 3px 3px 0 #000;">
              <div style="display: flex; justify-content: space-between; padding: 12px 0; border-bottom: 1px solid #E5E5E5;">
                <span style="font-size: 13px; color: #666; font-weight: 500;">Total Messages</span>
                <span style="font-size: 18px; font-weight: 700; color: #2D63EB;">${wellnessData.totalMessages}</span>
              </div>
              <div style="display: flex; justify-content: space-between; padding: 12px 0; border-bottom: 1px solid #E5E5E5;">
                <span style="font-size: 13px; color: #666; font-weight: 500;">Check-ins Completed</span>
                <span style="font-size: 18px; font-weight: 700; color: #2D63EB;">${wellnessData.checkInsCompleted}</span>
              </div>
              <div style="display: flex; justify-content: space-between; padding: 12px 0; border-bottom: 1px solid #E5E5E5;">
                <span style="font-size: 13px; color: #666; font-weight: 500;">Current Streak</span>
                <span style="font-size: 18px; font-weight: 700; color: #2DD36F;">${wellnessData.currentStreak} days</span>
              </div>
              <div style="display: flex; justify-content: space-between; padding: 12px 0;">
                <span style="font-size: 13px; color: #666; font-weight: 500;">Longest Streak</span>
                <span style="font-size: 18px; font-weight: 700; color: #2D63EB;">${wellnessData.longestStreak} days</span>
              </div>
            </div>
          </div>

          <!-- Crisis Support Section -->
          <div style="margin-bottom: 30px;">
            <div style="display: flex; align-items: center; gap: 10px; margin-bottom: 15px; padding-bottom: 10px; border-bottom: 2.5px solid #000;">
              <div style="width: 35px; height: 35px; background: #FFD100; border: 2px solid #000; border-radius: 7px; display: flex; align-items: center; justify-content: center; font-size: 18px;">🆘</div>
              <h2 style="font-size: 20px; font-weight: 800; color: #000; margin: 0;">Crisis Support Log</h2>
            </div>

            ${wellnessData.crisisEvents.length > 0 ? wellnessData.crisisEvents.map(event => `
              <div style="padding: 15px; margin-bottom: 10px; background: #FFF5F5; border: 2px solid #FF4A60; border-radius: 8px;">
                <div style="font-weight: 700; color: #FF4A60; margin-bottom: 7px; font-size: 13px;">${event.date} - ${event.severity} Severity</div>
                <div style="font-size: 12px; margin-bottom: 5px;">Status: ${event.resolved ? '✓ Resolved' : 'In Progress'}</div>
                <div style="font-size: 12px; color: #666; margin-top: 7px;">Resources Provided: ${event.resourcesProvided.join(', ')}</div>
              </div>
            `).join('') : '<div style="background: #fff; border: 2px solid #000; border-radius: 10px; padding: 20px; box-shadow: 3px 3px 0 #000;"><p style="text-align: center; color: #2DD36F; margin: 0;">No crisis events recorded - Great job maintaining your wellbeing! 🌟</p></div>'}
          </div>

          <!-- Key Insights Section -->
          <div style="margin-bottom: 30px;">
            <div style="display: flex; align-items: center; gap: 10px; margin-bottom: 15px; padding-bottom: 10px; border-bottom: 2.5px solid #000;">
              <div style="width: 35px; height: 35px; background: #FFD100; border: 2px solid #000; border-radius: 7px; display: flex; align-items: center; justify-content: center; font-size: 18px;">✨</div>
              <h2 style="font-size: 20px; font-weight: 800; color: #000; margin: 0;">Key Insights</h2>
            </div>

            ${wellnessData.insights.map(insight => `
              <div style="background: #E8F5E9; border: 2px solid #2DD36F; border-radius: 10px; padding: 15px; margin-bottom: 10px; font-size: 13px;">
                <span style="font-size: 20px; margin-right: 10px;">💡</span>${insight}
              </div>
            `).join('')}
          </div>

          <!-- Footer -->
          <div style="margin-top: 40px; padding-top: 20px; border-top: 2px solid #E5E5E5; text-align: center; color: #999; font-size: 11px;">
            <div style="display: inline-flex; align-items: center; gap: 7px; margin-bottom: 10px;">
              <div style="width: 20px; height: 20px; background: #2D63EB; border-radius: 5px; display: inline-flex; align-items: center; justify-content: center; color: white; font-weight: 900; font-size: 12px; border: 2px solid #000;">K</div>
              <strong style="color: #000;">KOI</strong>
            </div>
            <div>Generated on ${wellnessData.reportDate}</div>
            <div style="margin-top: 7px;">Private · Encrypted · Your Data, Your Control</div>
          </div>
        </div>
      `;

      // PDF configuration
      const opt = {
        margin: 10,
        filename: `koi-wellness-report-${new Date().toISOString().split('T')[0]}.pdf`,
        image: { type: 'jpeg', quality: 0.98 },
        html2canvas: { scale: 2, useCORS: true },
        jsPDF: { unit: 'mm', format: 'a4', orientation: 'portrait' }
      };

      // Generate PDF blob
      const pdfOutput = await html2pdf().from(container).set(opt).outputPdf('blob');
      const blob = new Blob([pdfOutput], { type: 'application/pdf' });

      setPdfBlob(blob);
      setIsExporting(false);
      setExportComplete(true);
    }, 5100);
  };

  const handleDownload = () => {
    if (!pdfBlob) return;

    const url = URL.createObjectURL(pdfBlob);
    const link = document.createElement('a');
    link.href = url;
    link.download = `koi-wellness-report-${new Date().toISOString().split('T')[0]}.pdf`;
    link.click();
    URL.revokeObjectURL(url);
  };

  return (
    <div style={{ padding: '1.5rem', maxWidth: '480px', margin: '0 auto', minHeight: '100vh' }}>
      <BackButton />

      <h1
        style={{
          fontWeight: 900,
          fontSize: '2rem',
          letterSpacing: '-0.03em',
          color: '#000',
          marginBottom: '0.5rem',
        }}
      >
        Export Wellness Report
      </h1>
      <p style={{ fontSize: '0.95rem', color: '#666', marginBottom: '2rem' }}>
        Download your complete wellness journey as a beautifully formatted PDF
      </p>

      {/* Preview Card */}
      <div
        style={{
          background: '#fff',
          border: '2.5px solid #000',
          borderRadius: '1.5rem',
          boxShadow: '6px 6px 0 #000',
          padding: '2rem',
          marginBottom: '2rem',
          transition: 'all 0.3s ease',
        }}
        onMouseEnter={(e) => {
          e.currentTarget.style.boxShadow = '8px 8px 0 #000';
          e.currentTarget.style.transform = 'translateY(-2px)';
        }}
        onMouseLeave={(e) => {
          e.currentTarget.style.boxShadow = '6px 6px 0 #000';
          e.currentTarget.style.transform = 'translateY(0)';
        }}
      >
        <div style={{ display: 'flex', alignItems: 'center', gap: '1rem', marginBottom: '1.5rem' }}>
          <div
            style={{
              width: '64px',
              height: '64px',
              background: 'linear-gradient(135deg, #2D63EB 0%, #06b6d4 100%)',
              border: '3px solid #000',
              borderRadius: '16px',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              boxShadow: '4px 4px 0 rgba(0,0,0,0.2)',
            }}
          >
            <svg width="32" height="32" viewBox="0 0 24 24" fill="none" stroke="white" strokeWidth="2">
              <rect x="3" y="3" width="18" height="18" rx="2" />
              <line x1="3" y1="9" x2="21" y2="9" />
              <line x1="9" y1="21" x2="9" y2="9" />
            </svg>
          </div>
          <div style={{ flex: 1 }}>
            <h3 style={{ fontWeight: 800, fontSize: '1.1rem', marginBottom: '0.25rem' }}>
              Wellness Report
            </h3>
            <p style={{ fontSize: '0.85rem', color: '#666' }}>
              Your complete mental health journey
            </p>
          </div>
        </div>

        <div style={{
          background: '#F9F9F9',
          border: '2px solid #E5E5E5',
          borderRadius: '12px',
          padding: '1rem',
          marginBottom: '1.5rem'
        }}>
          <h4 style={{ fontWeight: 700, fontSize: '0.9rem', marginBottom: '0.75rem', color: '#000' }}>
            Report Includes
          </h4>

          <div style={{ display: 'flex', flexDirection: 'column', gap: '0.5rem' }}>
            {[
              { label: 'Mood Trends', desc: 'Visual charts & progression' },
              { label: 'Loneliness Tracking', desc: 'Connection scores over time' },
              { label: 'Conversation Themes', desc: 'What you talked about most' },
              { label: 'Activity Progress', desc: 'Check-ins, streaks, messages' },
              { label: 'Crisis Support Log', desc: 'Times KOI helped in crisis' },
              { label: 'Key Insights', desc: 'Personalized observations' },
            ].map((item, i) => (
              <div key={i} style={{ fontSize: '0.85rem' }}>
                <span style={{ fontWeight: 600, color: '#000' }}>• {item.label}</span>
                <span style={{ color: '#999' }}> - {item.desc}</span>
              </div>
            ))}
          </div>
        </div>

        {!isExporting && !exportComplete && (
          <button
            onClick={generatePDF}
            className="neo-btn-primary"
            style={{ width: '100%' }}
          >
            Generate Wellness Report ✦
          </button>
        )}

        {isExporting && (
          <div>
            <div style={{ marginBottom: '1rem' }}>
              <div style={{
                display: 'flex',
                justifyContent: 'space-between',
                alignItems: 'center',
                marginBottom: '0.75rem'
              }}>
                <span style={{ fontSize: '0.85rem', fontWeight: 700, color: '#000' }}>
                  {progress < 20 ? '📊 Analyzing mood patterns...' :
                   progress < 40 ? '💭 Extracting conversation themes...' :
                   progress < 60 ? '💙 Calculating loneliness trends...' :
                   progress < 80 ? '🎯 Compiling activity data...' :
                   progress < 95 ? '✨ Designing your report...' :
                   '🎉 Almost ready!'}
                </span>
                <span style={{ fontSize: '1.25rem', fontWeight: 900, color: '#2D63EB' }}>
                  {Math.round(progress)}%
                </span>
              </div>

              <div
                style={{
                  height: '12px',
                  background: '#F0F0F0',
                  borderRadius: '6px',
                  border: '2px solid #000',
                  overflow: 'hidden',
                  position: 'relative',
                }}
              >
                <div
                  style={{
                    height: '100%',
                    width: `${progress}%`,
                    background: 'linear-gradient(90deg, #2D63EB 0%, #06b6d4 50%, #FFD100 100%)',
                    transition: 'width 0.1s ease',
                    position: 'relative',
                  }}
                >
                  <div
                    style={{
                      position: 'absolute',
                      top: 0,
                      left: '-100%',
                      width: '100%',
                      height: '100%',
                      background: 'linear-gradient(90deg, transparent, rgba(255,255,255,0.4), transparent)',
                      animation: 'shimmer 1s infinite',
                    }}
                  />
                </div>
              </div>
            </div>

            <div style={{ textAlign: 'center', fontSize: '2.5rem', animation: 'bounce 0.6s ease-in-out infinite' }}>
              🦊
            </div>
          </div>
        )}

        {exportComplete && (
          <div style={{ textAlign: 'center' }}>
            <div
              style={{
                fontSize: '4rem',
                marginBottom: '1rem',
                animation: 'popIn 0.5s cubic-bezier(0.34, 1.56, 0.64, 1)'
              }}
            >
              ✅
            </div>
            <h3 style={{ fontWeight: 800, fontSize: '1.2rem', marginBottom: '0.5rem' }}>
              Report Ready!
            </h3>
            <p style={{ fontSize: '0.9rem', color: '#666', marginBottom: '1.5rem' }}>
              Your wellness report is ready to download
            </p>

            {/* Heartbeat Download Button */}
            <button
              onClick={handleDownload}
              className="neo-btn-primary heartbeat-button"
              style={{
                width: '100%',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                gap: '0.5rem'
              }}
            >
              <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                <path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4" />
                <polyline points="7 10 12 15 17 10" />
                <line x1="12" y1="15" x2="12" y2="3" />
              </svg>
              Download PDF Now
            </button>
          </div>
        )}
      </div>

      {/* Info Section */}
      <div
        style={{
          background: 'var(--neo-yellow)',
          border: '2.5px solid #000',
          borderRadius: '1.25rem',
          boxShadow: '4px 4px 0 #000',
          padding: '1.25rem',
        }}
      >
        <div style={{ display: 'flex', gap: '0.75rem' }}>
          <span style={{ fontSize: '1.5rem', flexShrink: 0 }}>💡</span>
          <div>
            <h4 style={{ fontWeight: 700, fontSize: '0.9rem', marginBottom: '0.5rem' }}>
              Your Privacy Matters
            </h4>
            <ul style={{ margin: 0, paddingLeft: '1.25rem', fontSize: '0.85rem', color: '#333', lineHeight: '1.7' }}>
              <li>Report generated locally on your device</li>
              <li>All data remains encrypted</li>
              <li>No personal information shared</li>
              <li>Download & keep forever</li>
            </ul>
          </div>
        </div>
      </div>

      <style jsx>{`
        @keyframes shimmer {
          0% { left: -100%; }
          100% { left: 100%; }
        }
        @keyframes bounce {
          0%, 100% { transform: translateY(0); }
          50% { transform: translateY(-10px); }
        }
        @keyframes popIn {
          0% {
            opacity: 0;
            transform: scale(0.5);
          }
          100% {
            opacity: 1;
            transform: scale(1);
          }
        }

        /* Heartbeat animation - 2 pops, rest 5s, repeat */
        @keyframes heartbeat {
          0% { transform: scale(1); }
          7% { transform: scale(1.08); }
          14% { transform: scale(1); }
          21% { transform: scale(1.08); }
          28% { transform: scale(1); }
          100% { transform: scale(1); }
        }

        .heartbeat-button {
          animation: heartbeat 7s ease-in-out infinite;
        }

        .heartbeat-button:hover {
          animation: none !important;
        }
      `}</style>
    </div>
  );
}
