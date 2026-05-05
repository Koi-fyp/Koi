export const useRouter = () => ({
  replace: jest.fn(),
  push: jest.fn(),
  back: jest.fn(),
  prefetch: jest.fn(),
});

export const usePathname = () => '/';
export const useSearchParams = () => new URLSearchParams();
