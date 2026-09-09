import React from 'react';
import { act, cleanup, render, screen } from '@testing-library/react';
import { afterEach, describe, expect, it, vi } from 'vitest';

const state = vi.hoisted(() => ({ refetch: vi.fn(), data: { contractVersion: 1, status: 'awaitingOnboarding', onboardingStarted: false } }));
vi.mock('next/router', () => ({ useRouter: () => ({ query: { id: 'relationship-opaque-id' } }) }));
vi.mock('../../src/api/ApiCall', () => ({
  ApiGetCall: () => ({ data: state.data, refetch: state.refetch, isError: false }),
  ApiPostCall: () => { throw new Error('Observation must not create a mutation'); },
}));
vi.mock('../../src/layouts/index.js', () => ({ Layout: ({ children }) => <>{children}</> }));
vi.mock('../../src/components/CippCards/CippPageCard', () => ({ default: ({ children }) => <>{children}</> }));
import Page from '../../src/pages/tenant/gdap-management/onboarding/status';

afterEach(() => { cleanup(); vi.useRealTimers(); vi.clearAllMocks(); });
describe('GDAP read-only handoff', () => {
  it('polls without a submit action, then stops after the observation deadline', () => {
    vi.useFakeTimers();
    state.data = { contractVersion: 1, status: 'awaitingOnboarding', onboardingStarted: false };
    render(<Page />);
    act(() => vi.advanceTimersByTime(5000));
    expect(state.refetch).toHaveBeenCalledTimes(1);
    act(() => vi.advanceTimersByTime(175000));
    expect(screen.getByText(/Onboarding start has not been confirmed/)).toBeInTheDocument();
    const calls = state.refetch.mock.calls.length;
    act(() => vi.advanceTimersByTime(20000));
    expect(state.refetch).toHaveBeenCalledTimes(calls);
  });
  it('recognizes a finished attempt as evidence that onboarding started', () => {
    state.data = { contractVersion: 1, status: 'failed', onboardingStarted: true };
    render(<Page />);
    expect(screen.getByText(/CIPP has started onboarding/)).toBeInTheDocument();
  });
});
