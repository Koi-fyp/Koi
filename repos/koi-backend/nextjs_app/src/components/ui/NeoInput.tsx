'use client';
import { InputHTMLAttributes, TextareaHTMLAttributes } from 'react';

interface BaseProps {
  label?: string;
  error?: string;
  containerClassName?: string;
}

type InputProps = BaseProps &
  InputHTMLAttributes<HTMLInputElement> & { as?: 'input' };

type TextareaProps = BaseProps &
  TextareaHTMLAttributes<HTMLTextAreaElement> & { as: 'textarea' };

type NeoInputProps = InputProps | TextareaProps;

export default function NeoInput({
  label,
  error,
  containerClassName = '',
  as,
  className = '',
  ...props
}: NeoInputProps & { as?: 'input' | 'textarea'; className?: string }) {
  const inputClass = ['neo-input', error && 'border-red-500', className]
    .filter(Boolean)
    .join(' ');

  return (
    <div className={['flex flex-col gap-1', containerClassName].filter(Boolean).join(' ')}>
      {label && (
        <label
          style={{
            fontFamily: 'var(--font-display)',
            fontWeight: 700,
            fontSize: '0.875rem',
            color: '#000',
          }}
        >
          {label}
        </label>
      )}
      {as === 'textarea' ? (
        <textarea
          {...(props as TextareaHTMLAttributes<HTMLTextAreaElement>)}
          className={inputClass}
        />
      ) : (
        <input
          {...(props as InputHTMLAttributes<HTMLInputElement>)}
          className={inputClass}
        />
      )}
      {error && (
        <span
          style={{
            fontFamily: 'var(--font-body)',
            fontSize: '0.75rem',
            color: '#FF4136',
            fontWeight: 500,
          }}
        >
          {error}
        </span>
      )}
    </div>
  );
}
