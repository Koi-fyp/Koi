import type { Config } from 'tailwindcss';

const config: Config = {
  content: [
    './src/pages/**/*.{js,ts,jsx,tsx,mdx}',
    './src/components/**/*.{js,ts,jsx,tsx,mdx}',
    './src/app/**/*.{js,ts,jsx,tsx,mdx}',
  ],
  theme: {
    extend: {
      fontFamily: {
        display: ['Bricolage Grotesque', 'system-ui', 'sans-serif'],
        body:    ['DM Sans', 'system-ui', 'sans-serif'],
        inter:   ['DM Sans', 'system-ui', 'sans-serif'], // redirect legacy class
      },
      colors: {
        neo: {
          blue:   '#2D63EB',
          yellow: '#FFD100',
          black:  '#000000',
          white:  '#FFFFFF',
          gray:   '#F4F4F4',
          muted:  '#6B7280',
          coral:  '#FF6B6B',
          mint:   '#2DD36F',
          purple: '#845EC2',
          orange: '#FF9F43',
        },
      },
      borderRadius: {
        neo: '1.25rem',
        koi: '2.5rem',
        xl2: '1rem',
        xl3: '1.5rem',
        xl4: '2rem',
      },
      boxShadow: {
        'neo-sm':    '3px 3px 0 0 #000',
        'neo-md':    '4px 4px 0 0 #000',
        'neo-lg':    '6px 6px 0 0 #000',
        'neo-xl':    '8px 8px 0 0 #000',
        'neo-focus': '0 0 0 3px rgba(45,99,235,0.2)',
        bubbly:      '0 8px 0px 0px rgba(0,0,0,0.05)',
        card:        '0 4px 24px 0 rgba(0,0,0,0.08)',
        'card-lg':   '0 8px 48px 0 rgba(0,0,0,0.12)',
      },
      animation: {
        'float-slow':  'floatY 5s ease-in-out infinite',
        'float-mid':   'floatY 4s ease-in-out infinite 0.7s',
        'float-fast':  'floatY 3s ease-in-out infinite 1.4s',
        'spin-slow':   'spin 8s linear infinite',
        'fade-up':     'fadeUp 0.6s ease both',
        'slide-right': 'slideRight 0.5s ease both',
        'pulse-dot':   'pulseDot 2s ease-in-out infinite',
      },
      keyframes: {
        floatY: {
          '0%, 100%': { transform: 'translateY(0px)' },
          '50%':       { transform: 'translateY(-12px)' },
        },
        fadeUp: {
          from: { opacity: '0', transform: 'translateY(20px)' },
          to:   { opacity: '1', transform: 'translateY(0)' },
        },
        slideRight: {
          from: { opacity: '0', transform: 'translateX(-16px)' },
          to:   { opacity: '1', transform: 'translateX(0)' },
        },
        pulseDot: {
          '0%, 100%': { opacity: '1' },
          '50%':       { opacity: '0.4' },
        },
      },
    },
  },
  plugins: [],
};

export default config;
